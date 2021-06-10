-- -----------------------------------------------------------------------------
-- L_AutoVirtualThermostat.lua
-- Copyright 2017,2020 Patrick H. Rigney, All Rights Reserved
-- http://www.toggledbits.com/avt/
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
-- -----------------------------------------------------------------------------

--[[ ABOUT THIS VERSION/BRANCH:
     "devicetype" branch (development) -- use standard vera device type for thermostat
     Requires device type: urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1
              static JSON: D_HVAC_ZoneTwoSetPointsThermostat1.json
     Of course, this disables the configuration UI and JavaScript, so need to go to parent-child
     and put the configuration interface on the parent.
]]

module("L_AutoVirtualThermostat1", package.seeall)

local _PLUGIN_ID = 8956
local _PLUGIN_NAME = "AutoVirtualThermostat"
local _PLUGIN_VERSION = "1.6devicetype-20020"
local _PLUGIN_URL = "https://www.toggledbits.com/avt"
local _CONFIGVERSION = 19138

local debugMode = true
local MAXEVENTS = 100

local MYSID = "urn:toggledbits-com:serviceId:AutoVirtualThermostat1"
local MYTYPE = "urn:schemas-toggledbits-com:device:AutoVirtualThermostat:1"

local OPMODE_SID = "urn:upnp-org:serviceId:HVAC_UserOperatingMode1"
local OPSTATE_SID = "urn:micasaverde-com:serviceId:HVAC_OperatingState1"
local FANMODE_SID = "urn:upnp-org:serviceId:HVAC_FanOperatingMode1"
local SETPOINT_SID = "urn:upnp-org:serviceId:TemperatureSetpoint1"
local TEMPSENS_SID = "urn:upnp-org:serviceId:TemperatureSensor1"
local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local SWITCH_SID = "urn:upnp-org:serviceId:SwitchPower1"

local EMODE_NORMAL = "Normal"
local EMODE_ECO = "EnergySavingsMode"

local pluginDevice = false;
local runStamp = 0
local children = {}
local devState = {}
local devTasks = nil
local eventList = {}
local sysTemps = { unit="F", default=72, minimum=41, maximum=95 }

local isALTUI = false
local isOpenLuup = false

local json = require('dkjson')
if not json then require('json') end
if not json then luup.log(_PLUGIN_NAME .. ": can't find JSON module",1) return end

local function dump(t)
    if t == nil then return "nil" end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            val = dump(v)
        elseif type(v) == "function" then
            val = "(function)"
        elseif type(v) == "string" then
            val = string.format("%q", v)
        elseif type(v) == "number" then
            local d = v - os.time()
            if d < 0 then d = -d end
            if d <= 86400 then
                val = string.format("%d (%s)", v, os.date("%X", v))
            else
                val = tostring(v)
            end
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...) -- luacheck: ignore 212
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = _PLUGIN_NAME .. ": " .. tostring(msg)
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            elseif type(val) == "number" then
                local d = val - os.time()
                if d < 0 then d = -d end
                if d <= 86400 then
                    val = string.format("%d (time %s)", val, os.date("%X", val))
                end
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
    table.insert( eventList, { level=level, time=os.time(), msg=str } )
    while #eventList > MAXEVENTS do table.remove( eventList, 1 ) end
end

local function D(msg, ...)
    if debugMode then
        L({msg=msg,prefix=_PLUGIN_NAME.."(debug)::"}, ... )
    end
end

local function split( str, sep )
    if sep == nil then sep = "," end
    local arr = {}
    if #str == 0 then return arr, 0 end
    local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
    table.insert( arr, rest )
    return arr, #arr
end

local function shallowcopy(t)
    local r = {}
    for k,v in pairs(t) do
        r[k] = v
    end
    return r
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
    assert(name ~= nil)
    assert(dev ~= nil)
    if serviceId == nil then serviceId = MYSID end
    local s = luup.variable_get(serviceId, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

local function limit( n, nMin, nMax )
    n = tonumber(n, 10)
    if n == nil or n < nMin then return nMin end
    if n > nMax then return nMax end
    return n
end

-- Get mean of an array of values, return to prec decimals. The rounding makes
-- it possible that the mean can be less than or greater than the range of
-- array values (e.g. mean of 8.1 and 8.3 with prec=0 yields 8), so enforce
-- min/max from array value range. Returns mean, min and max.
local function mean( a, prec )
    local sum = 0
    local mini = a[1]
    local maxi = mini
    for _,v in ipairs(a) do sum = sum + v if v < mini then mini = v elseif v > maxi then maxi = v end end
    sum = sum / #a
    local d = 10^prec
    local ret = math.floor( sum * d + 0.5 ) / d
    if ret < mini then ret = mini elseif ret > maxi then ret = maxi end
    return ret, mini, maxi
end

local function saveDeviceState( dev )
    luup.variable_set( MYSID, "State", json.encode( { timestamp=os.time(), devState=devState } ), dev )
end

local function restoreDeviceState( dev )
    local st = luup.variable_get( MYSID, "State", dev ) or ""
    if st ~= "" then
        local obj, pos, err
        obj, pos, err = json.decode( st )
        D("restoreDeviceState() loaded %1, err %2 pos %3", obj, err, pos)
        if obj ~= nil and type(obj.devState) == "table" and (os.time()-obj.timestamp) < 120 then
            devState = obj.devState
            return true
        end
    end
    devState = {}
    return false
end

local function setDeviceState( ahu, name, value, dev )
    ahu = tostring(ahu)
    devState[ahu] = devState[ahu] or {}
    devState[ahu][name] = value
    saveDeviceState( dev )
end

local function getDeviceState( ahu, name, dev, dflt )
    ahu = tostring(ahu)
    return (devState[ahu] or {})[name] or dflt
end

local function deviceOnOff( targetDevice, state, vtDev )
    assert(type(state) == "boolean")
    local targetId
    if type(targetDevice) == "string" then
        targetId = getVarNumeric( targetDevice, 0, vtDev, MYSID )
    else
        targetId = tonumber(targetDevice) or 0
    end
    if targetId > 0 and luup.devices[targetId] ~= nil then
        local oldState = getVarNumeric("Status", 0, targetId, SWITCH_SID)
        state = state and "1" or "0" -- force strings (openLuup/VSwitch compat)
        if luup.devices[targetId].device_type == "urn:schemas-upnp-org:device:VSwitch:1" then
            -- VSwitch special action
            luup.call_action("urn:upnp-org:serviceId:VSwitch1", "SetTarget", { newTargetValue=state }, targetId)
        elseif luup.device_supports_service(SWITCH_SID, targetId) then
            -- Generic binary switch action
            luup.call_action(SWITCH_SID, "SetTarget", { newTargetValue=state }, targetId)
        else
            L({level=2,msg="Don't know how to control target %1"}, targetId)
            return false
        end
        D("deviceOnOff() %1 changed from %2 to %3", targetDevice, oldState, state)
        return state ~= oldState
    else
        D("deviceOnOff(): no target for %1", targetDevice)
    end
    return false
end

local function nextRun(stepStamp)
    D("nextRun(%1) with %2", stepStamp, devTasks)
    -- Schedule next run if there's work yet to do.
    local soonest = nil
    if devTasks then soonest = devTasks.time end
    local delay = getVarNumeric( "Interval", 60, pluginDevice )
    if soonest ~= nil then
        local now = os.time()
        delay = soonest - now
        if delay < 1 then delay = 1 end
    end
    D("nextRun() scheduling for %1 from now", delay)
    luup.call_delay( "avtDelayCallback", delay, string.format("%d:%d", stepStamp, pluginDevice) )
end

-- Find task
local function findTask( dev, taskType )
    local lt = devTasks
    local pt = nil
    while lt ~= nil do
        if lt.dev == dev and lt.type == taskType then
            break
        else
            pt = lt
            lt = lt.next
        end
    end
    return lt, pt
end

-- Remove currently scheduled task matching type for device
local function clearTask( dev, taskType )
    D("clearTask(%1,%2)", dev, taskType)
    -- Remove any currently scheduled task of the same type.
    local lt, pt = findTask( dev, taskType )
    if lt ~= nil then
        D("clearTask() removing prior %1 by %2", lt.type, lt.caller)
        if pt == nil then
            devTasks = lt.next
        else
            pt.next = lt.next
        end
        lt.next = nil
    end
    return lt, pt
end

-- Insert task into task list. That's all.
local function insertTask( t )
    D("insertTask(%1)", t)
    clearTask( t.dev, t.type )
    if t.caller == nil then t.caller = debug.getinfo(2, "n") end
    -- Insert ourselves in list, in time order (least to greatest)
    local lt = devTasks
    local pt = nil
    D("insertTask() insert %2 scanning %1", lt, t)
    while lt do
        if lt.time > t.time then
            break
        end
        pt = lt
        lt = lt.next
    end
    t.next = lt
    if not pt then
        devTasks = t
    else
        pt.next = t
    end
end

-- Insert and schedule a task.
local function scheduleTask( pdev, taskObj )
    D("scheduleTask(%1,%2)", pdev, taskObj)
    assert(type(taskObj) == "table")

    local soonest = nil
    if devTasks then soonest = devTasks.time end

    local t = shallowcopy(taskObj)
    t.caller = debug.getinfo(2, "n")
    t.time = t.time or os.time()
    t.dev = t.dev or pdev
    insertTask( t )

    -- If new task runs sooner than head task, need to reschedule
    if soonest == nil or t.time < soonest then
        -- Bump runStamp (thread identifier) and immediately scan for tasks to run.
        runStamp = runStamp + 1
        D("scheduleTask() starting new timer thread %1", runStamp)
        nextRun(runStamp, pluginDevice)
    end
end

-- Reschedule a task for a new time
local function rescheduleTask( tdev, taskType, newTime )
    D("rescheduleTask(%1,%2,%3)", tdev, taskType, newTime)
    local t = devTasks
    local pt = nil
    while t ~= nil do
        if t.dev == tdev and t.type == taskType then
            if t.time < newTime then
                D("rescheduleTasks() found task, not rescheduling, current task is earlier, %1", t.time)
                return true
            end
            D("rescheduleTasks() found task, unlinking and rescheduling")
            if pt == nil then
                devTasks = t.next
            else
                pt.next = t.next
            end
            t.next = nil
            t.time = newTime
            scheduleTask( tdev, t )
            return true
        end
        pt = t
        t = t.next
    end
    return false
end

-- Handle timer task (handler for delay, called by callback in impl file)
function runTask(p)
    D("runTask(%1)", p)
    local stepStamp
    stepStamp = string.match(p, "(%d+):(%d+)")
    stepStamp = tonumber(stepStamp)
    if stepStamp ~= runStamp then
        D("runTask() stamp mismatch (got %1, expected %2). Newer thread running! I'm out...", stepStamp, runStamp)
        return
    end

    -- Check tasks, run as needed. Remove as we run them, unless recurring.
    while devTasks and devTasks.time <= os.time() do
        local t = shallowcopy(devTasks)
        -- Remove from queue
        devTasks = devTasks.next

        -- Run it
        local status, err, f
        D("runTask() running %1 by %2, func %4, dev %3", t.type, t.caller, t.dev, t.func)
        if type(t.func) == "string" then
            local s = string.format("return %s(%d,%d)", t.func, t.dev, pluginDevice)
            f = loadstring(s)
        else
            f = t.func
        end
        status, err = pcall( f, t.dev, pluginDevice )
        if not status then
            D("Task %1 by %3 failed, %2", t.type, err, t.caller)
        end

        -- If recurring, put it back in the queue
        if t.recurring then
            assert(t.recurring > 0)
            -- Recurring, schedule next run
            t.time = os.time() + t.recurring
            insertTask( t )
        end
    end

    if stepStamp == runStamp then
        D("runTask() finished; scheduling next run in same thread")
        nextRun(stepStamp, pluginDevice)
    else
        D("runTask() finished. New tasks have been scheduled; letting this thread (%1) die.", stepStamp)
    end
end

local statusMap = { ['FanOnly']="Fan Only" }
local function updateDisplayStatus( dev )
    D("updateDisplayStatus(%1)", dev)
    local modeStatus = luup.variable_get( OPSTATE_SID, "ModeState", dev ) or "Idle"
    local fanStatus = luup.variable_get( FANMODE_SID, "FanStatus", dev )
    modeStatus = statusMap[modeStatus] or modeStatus
    if modeStatus == "Idle" and fanStatus == "On" then
        modeStatus = "Fan Only"
    end
    luup.variable_set( MYSID, "DisplayStatus", modeStatus, dev )
end

local function markCycle(dev)
    setDeviceState( dev, "cycleStart", os.time(), dev )
    luup.variable_set( MYSID, "CycleTime", "", dev )
end

-- Turn fan off (unconditionally).
local function fanOff(dev)
    D("fanOff(%1)", dev)
    deviceOnOff("FanDevice", false, dev)
    luup.variable_set(FANMODE_SID, "FanStatus", "Off", dev)
    updateDisplayStatus(dev)
end

-- Turn fan on (unconditionall)
local function fanOn(dev)
    D("fanOn(%1)", dev)
    deviceOnOff("FanDevice", true, dev)
    luup.variable_set(FANMODE_SID, "FanStatus", "On", dev)
    updateDisplayStatus(dev)
end

-- Run periodic fan. Periodic cycling is currently a fixed 15 minutes per hour.
local fanPeriodicOff = function(dev) end -- temporary forward declaration
local function fanPeriodicOn(dev)
    D("fanPeriodicOn(%1)", dev)
    local currentState = luup.variable_get(OPSTATE_SID, "ModeState", dev) or "Idle"
    if currentState == "Idle" then
        -- Run for 15 minutes
        local runTime = limit( getVarNumeric( "FanCycleMinsPerHr", 15, dev ), 1, 59 )
        fanOn(dev)
        scheduleTask( dev, { ['type']='fan', func=fanPeriodicOff, dev=dev, ['time']=os.time()+(runTime*60) } )
    end
end

-- Stop periodic fan
fanPeriodicOff = function(dev) -- redeclaration (forward above)
    D("fanPeriodicOff(%1)", dev)
    local currentState = luup.variable_get(OPSTATE_SID, "ModeState", dev) or "Idle"
    if currentState == "Idle" or currentState == "Off" then
        fanOff(dev)
    end
    if currentState == "Idle" then
        local runTime = limit( getVarNumeric( "FanCycleMinsPerHr", 15, dev ), 1, 59 )
        scheduleTask( dev, { ['type']='fan', func=fanPeriodicOn, dev=dev, ['time']=os.time()+((60-runTime)*60) } )
    end
end

-- Turn fan off if we're in auto mode.
local function fanAutoOff(dev)
    D("fanAutoOff(%1)", dev)
    local mode = luup.variable_get(FANMODE_SID, "Mode", dev) or "Auto"
    D("fanAutoOff() arming for fan mode %1", mode)
    if mode == "PeriodicOn" then
        fanPeriodicOff(dev)
    elseif mode ~= "ContinuousOn" then
        clearTask(dev, "fan")
        fanOff(dev)
    else
        -- For continuous on, off means on
        fanOn(dev)
    end
    updateDisplayStatus(dev)
end

-- Set ModeState to something appropriate for target when we're doing nothing.
local function setIdleModeStatus(dev)
    luup.variable_set(OPSTATE_SID, "ModeState", "Idle", dev)
    return "Idle"
end

-- Turn the heat off.
local function heatOff(dev)
    D("heatOff(%1)", dev)
    assert(dev ~= nil)

    if deviceOnOff("HeatingDevice", false, dev) then
        -- Save time for equipment delay, but only if we did real work.
        setDeviceState( dev, "heatLastOff", os.time(), dev )
    end

    local fanDelay = getVarNumeric( "FanOffDelayHeating", 60, dev )
    scheduleTask( dev, { ['type']="fan", func=fanAutoOff, dev=dev, ['time']=os.time()+fanDelay } )

    setIdleModeStatus(dev)

    local cycleStart = getDeviceState( dev, "cycleStart", dev, 0 )
    if cycleStart > 0 then
        local runTime = os.time() - cycleStart
        L("End heating cycle, %1 minutes %2 seconds", math.floor(runTime/60), runTime % 60)
        setDeviceState( dev, "cycleStart", 0, dev )
    end
end

-- Turn the cooling off.
local function coolOff(dev)
    D("coolOff(%1)", dev)
    assert(dev ~= nil)

    if deviceOnOff("CoolingDevice", false, dev) then
        -- Save time for equipment delay, but only if we did real work.
        setDeviceState( dev, "coolLastOff", os.time(), dev )
    end

    local fanDelay = getVarNumeric( "FanOffDelayCooling", 60, dev )
    scheduleTask( dev, { ['type']="fan", func=fanAutoOff, dev=dev, ['time']=os.time()+fanDelay } )

    setIdleModeStatus(dev)

    local cycleStart = getDeviceState( dev, "cycleStart", dev, 0 )
    if cycleStart > 0 then
        local runTime = os.time() - cycleStart
        L("End cooling cycle, %1 minutes %2 seconds", math.floor(runTime/60), runTime % 60)
        setDeviceState( dev, "cycleStart", 0, dev )
    end
end

local function goIdle( dev, currState )
    D("goIdle(%1,%2)", dev, currState)
    currState = currState or luup.variable_get( OPSTATE_SID, "ModeState", dev ) or "Idle"
    coolOff(dev)
    heatOff(dev)

    local currTarget = luup.variable_get( OPMODE_SID, "ModeTarget", dev ) or "Off"
    if currTarget ~= "Off" then
        -- See if fan needs to be on
        local fanMode = luup.variable_get(FANMODE_SID, "Mode", dev) or "Auto"
        if fanMode == "ContinuousOn" then
            local fanStatus = luup.variable_get(FANMODE_SID, "FanStatus", dev) or "Off"
            if fanStatus ~= "On" then
                -- Unconditionally on.
                clearTask(dev, "fan")
                fanOn(dev)
            end
        elseif fanMode == "PeriodicOn" then
            -- If no other fan task is pending, start the periodic task
            local task = findTask( dev, "fan" )
            if task == nil then
                fanPeriodicOff( dev )
            end
        end
    end
end

local function taskIdle( tdev, pdev )
    goIdle( tdev )
end

-- Turn heating unit on.
local function heatOn(dev)
    D("heatOn(%1)", dev)
    deviceOnOff("HeatingDevice", true, dev)
end

-- Handle call for heating.
local function callHeat(dev)
    D("callHeat(%1)", dev)
    local now = os.time()
    local lastOff = getDeviceState( dev, "heatLastOff", dev, 0 )
    local equipDelay = lastOff + getVarNumeric("EquipmentDelay", 300, dev)
    if equipDelay > now then
        L{level=2,msg="Call for heating delayed by equipment delay"}
        luup.variable_set(OPSTATE_SID, "ModeState", "Delayed", dev)
        rescheduleTask(dev, "sense", equipDelay)
        return false
    end

    coolOff( dev )

    L("Heating!")
    luup.variable_set(OPSTATE_SID, "ModeState", "Heating", dev)
    markCycle(dev)

    local delay = getVarNumeric( "FanOnDelayHeating", 0, dev )
    if delay < 0 then
        -- If delay < 0, then start heating first, then fan
        scheduleTask( dev, { ['type']="heat", func=heatOn, dev=dev } )
        scheduleTask( dev, { ['type']="fan", func=fanOn, dev=dev, ['time']=now-delay } )
    else
        -- Normal delay, fan first, then heater
        scheduleTask( dev, { ['type']="fan", func=fanOn, dev=dev } )
        scheduleTask( dev, { ['type']="heat", func=heatOn, dev=dev, ['time']=now+delay } )
    end
    return true
end

-- Turn cooling unit on.
local function coolOn(dev)
    D("coolOn(%1)", dev)
    deviceOnOff("CoolingDevice", true, dev)
end

-- Handle call for cooling.
local function callCool(dev)
    D("callCool(%1)", dev)
    local now = os.time()
    local lastOff = getDeviceState( dev, "coolLastOff", dev, 0 )
    local equipDelay = lastOff + getVarNumeric("EquipmentDelay", 300, dev)
    if equipDelay > now then
        L{level=2,msg="Call for cooling delayed by equipment delay"}
        luup.variable_set(OPSTATE_SID, "ModeState", "Delayed", dev)
        rescheduleTask(dev, "sense", equipDelay)
        return false
    end

    heatOff( dev )

    L("Cooling!")
    luup.variable_set(OPSTATE_SID, "ModeState", "Cooling", dev)
    markCycle(dev)

    local delay = getVarNumeric( "FanOnDelayCooling", 0, dev )
    if delay < 0 then
        -- If delay < 0, then start cooling first, then fan
        scheduleTask( dev, { ['type']="cool", func=coolOn, dev=dev } )
        scheduleTask( dev, { ['type']="fan", func=fanOn, dev=dev, ['time']=now-delay } )
    else
        scheduleTask( dev, { ['type']="fan", func=fanOn, dev=dev } )
        scheduleTask( dev, { ['type']="cool", func=coolOn, dev=dev, ['time']=now+delay } )
    end
    return true
end

local function checkSchedule(dev)
    local sc = luup.variable_get( MYSID, "Schedule", dev ) or ""
    local t = split(sc,"-")
    if #t ~= 2 then return true end
    local tt = os.date("*t")
    local now = tt['hour'] * 60 + tt['min']
    local schedStart = tonumber(t[1],10)
    local schedEnd = tonumber(t[2],10)
    if schedStart == schedEnd then return true end
    if schedEnd < schedStart then
        -- Spans midnight
        if now >= schedStart or now < schedEnd then
            return true
        end
    elseif now >= schedStart and now < schedEnd then
        return true
    end
    local ms = luup.variable_get( OPSTATE_SID, "ModeState", dev ) or ""
    if ms ~= "Idle" then
        goIdle( dev, ms )
    end
    return false
end

local function round(n)
    if n < 0 then return math.ceil(n-0.5) end
    return math.floor(n+0.5)
end

local function constrain( val, valMin, valMax )
    if valMin ~= nil and val < valMin then val = valMin end
    if valMax ~= nil and val > valMax then val = valMax end
    return val
end

local function checkSensors(dev)
    D("checkSensors(%1)", dev)
    -- Check sensor(s), get current temperature.
    dev = tonumber( dev )
    assert(dev ~= nil)
    local modeStatus = luup.variable_get(OPSTATE_SID, "ModeState", dev) or "Idle"
    local currentTemp = 0
    local tst = split( luup.variable_get(MYSID, "TempSensors", dev) or "" )
    local tempCount = 0
    local now = os.time()
    local maxSensorDelay = getVarNumeric( "MaxSensorDelay", 3600, dev )
    local maxSensorBattery = getVarNumeric( "MaxSensorBattery", 7200, dev )
    local minBatteryLevel = getVarNumeric( "MinBatteryLevel", 1, dev )
    for _,ts in ipairs(tst) do
        local tnum = tonumber( ts )
        if tnum ~= nil and luup.devices[tnum] ~= nil then
            local temp, since, rawTemp
            rawTemp,since = luup.variable_get( TEMPSENS_SID, "CurrentTemperature", tnum )
            if rawTemp ~= nil then temp = tonumber(rawTemp) else temp = nil end
            since = tonumber( since or 0 ) or 0
            D("checkSensors() temp sensor %1 (%2) temp %3 since %4 (raw %5)",
                ts, luup.devices[tnum].description, temp, since, rawTemp)
            local valid = true -- innocent until proven guilty
            -- Not all devices signal CommFailure, so default to assume OK.
            if getVarNumeric( "IgnoreCommFailure", 0, dev ) == 0 then
                local cflag = getVarNumeric( "CommFailure", 0, tnum, HADEVICE_SID )
                if cflag ~= 0 then
                    valid = false
                    L("Sensor %1 (%2) ineligible, comm failure status %3", ts, luup.devices[tnum], cflag)
                end
            end
            -- Did we get a valid temperature reading?
            if valid and temp == nil then
                valid = false
                L("Sensor %1 (%2) ineligible, invalid/non-numeric value: %3",
                    ts, luup.devices[tnum].description, rawTemp)
            end
            if valid and maxSensorDelay > 0 and ((now-since) > maxSensorDelay) then
                valid = false
                L("Sensor %1 (%2) ineligible, last temperature update at %3 is more than %4 ago",
                    ts, luup.devices[tnum].description, since, maxSensorDelay)
            end
            if valid and (maxSensorBattery > 0 or minBatteryLevel > 0) then
                -- Check battery level and report date. Many sensors use child devices, so if our
                -- specified device doesn't have info for us, look at its parent. Reliance here is
                -- based on http://wiki.micasaverde.com/index.php/Luup_UPnP_Variables_and_Actions#HaDevice1
                local parentDev = luup.devices[tnum].device_num_parent or 0
                local bsource = tnum
                local blevel = getVarNumeric( "BatteryLevel", nil, tnum, HADEVICE_SID )
                if blevel == nil and parentDev ~= 0 then
                    bsource = parentDev
                    blevel = getVarNumeric( "BatteryLevel", nil, parentDev, HADEVICE_SID )
                end
                -- Get battery date from wherever we ended up getting battery level.
                local bdate = getVarNumeric( "BatteryDate", nil, bsource, HADEVICE_SID )
                D("checkSensors() sensor %1 (%2) battery level %3 timestamp %4",
                    ts, luup.devices[tnum].description, blevel, bdate)
                -- Check report date first. Must be recent (if we're checking).
                if bdate ~= nil and maxSensorBattery > 0 and ((now-bdate) > maxSensorBattery) then
                    -- We have a timestamp, and it's out of limit
                    valid = false
                    L("Sensor %1 (%2) ineligible, last battery report %3 is more than %4 ago",
                        ts, luup.devices[tnum].description, bdate, maxSensorBattery)
                end
                -- If date is OK, check level (if checking level)
                if valid and minBatteryLevel > 0 and blevel ~= nil and blevel < minBatteryLevel then
                    -- Out of limit
                    valid = false
                    L("Sensor %1 (%2) ineligible, battery level %3 < allowed minimum %4",
                        ts, luup.devices[tnum].description, blevel, minBatteryLevel)
                end
            end
            if valid then
                D("checkSensors() sensor %1 (%2) valid temp reported=%3",
                    ts, luup.devices[tnum].description, temp)
                currentTemp = currentTemp + temp
                tempCount = tempCount + 1
            end
        else
            L("Sensor %1 ineligible, device not found", ts)
        end
    end
    D("checkSensors() TempSensors=%1, valid sensors=%2, total=%3", tst, tempCount, currentTemp)
    if tempCount == 0 then
        -- No valid sensors!
        L{level=1,msg="No valid sensors."}
        luup.variable_set( MYSID, "DisplayTemperature", "<span style='font-size:1.5em; font-weight: bold;'>--.-&deg;</span>", dev )
        luup.variable_set( MYSID, "Failure", "1", dev )
        scheduleTask( dev, { ['type']='goidle', func=taskIdle } )
        return
    end
    currentTemp = round(currentTemp * 10 / tempCount) / 10
    L("Found %1 valid sensors, average temp is %2", tempCount, currentTemp)
    luup.variable_set( TEMPSENS_SID, "CurrentTemperature", currentTemp, dev )
    luup.variable_set( HADEVICE_SID, "LastUpdate", now, dev )
    luup.variable_set( MYSID, "DisplayTemperature", string.format("<span style='font-size:1.5em; font-weight: bold;'>%.1f&deg;</span>", currentTemp), dev )
    luup.variable_set( MYSID, "Failure", "0", dev )

    -- Check for lockout
    local devLockout = getDeviceState( dev, "devLockout", dev, 0 )
    if devLockout > 0 then
        if now < devLockout then
            L({level=2,msg="Lockout in effect, %1 seconds to go..."}, devLockout - os.time())
            scheduleTask( dev, { ['type']='goidle', func=taskIdle, dev=dev } )
            return
        end
        L("Restoring from lockout")
        setDeviceState( dev, "devLockout", 0, dev )
        modeStatus = "Idle"
        luup.variable_set( OPSTATE_SID, "ModeState", modeStatus, dev )
    end

    local setpointTemp = getVarNumeric("CurrentSetpoint", sysTemps.default, dev, SETPOINT_SID)
    local differential = getVarNumeric("Differential", 1.5, dev)

    -- Check schedule
    if not checkSchedule( dev ) then
        goIdle( dev, modeStatus )
        return
    end

    -- Check current operating mode.
    D("checkSensors() current state is %1, temp %2, differential %4", modeStatus, currentTemp, setpointTemp, differential)
    local coolSP = getVarNumeric( "SetpointCooling", setpointTemp, dev, MYSID )
    local heatSP = getVarNumeric( "SetpointHeating", setpointTemp, dev, MYSID )
    if modeStatus == "Idle" or modeStatus == "Delayed" then
        -- See if we need to start up. (if delayed, go through motions, callCool/callHeat will determine if we can run)
        local modeTarget = luup.variable_get(OPMODE_SID, "ModeTarget", dev) or "Off"
        D("checkSensors() effective mode is %1, setpoints H=%2,C=%3, diff %4", modeTarget, heatSP, coolSP, differential)
        if (modeTarget == "AutoChangeOver" or modeTarget == "CoolOn") and (currentTemp >= (coolSP+differential)) then
            luup.variable_set( SETPOINT_SID, "SetpointAchieved", "0", dev )
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", coolSP, dev )
            callCool(dev)
        elseif (modeTarget == "AutoChangeOver" or modeTarget == "HeatOn") and (currentTemp <= (heatSP-differential)) then
            luup.variable_set( SETPOINT_SID, "SetpointAchieved", "0", dev )
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", heatSP, dev )
            callHeat(dev)
        else
            -- No change. Neither heating nor cooling should be running.
            deviceOnOff("HeatingDevice", false, dev)
            deviceOnOff("CoolingDevice", false, dev)
            -- Check fan operation.
            local fanMode = luup.variable_get(FANMODE_SID, "Mode", dev) or "Auto"
            local task = findTask( dev, "fan" )
            if fanMode == "ContinuousOn" then
                local fanStatus = luup.variable_get(FANMODE_SID, "FanStatus", dev) or "Off"
                if fanStatus ~= "On" then
                    clearTask(dev, "fan")
                    fanOn(dev)
                end
            elseif fanMode == "PeriodicOn" then
                if task == nil then
                    -- We're in PeriodicOn, so there should always be a task on the queue (on or off).
                    -- If no task, launch
                    L("Periodic fan task missing. Starting cycle.")
                    fanPeriodicOff( dev )
                end
            else
                if task == nil then
                    -- If no fan task pending, make sure fan is off.
                    fanOff( dev )
                end
            end
        end
    elseif modeStatus == "Cooling" or modeStatus == "Heating" then
        local coolMRT = getVarNumeric( "CoolMaxRuntime", 7200, dev)
        local heatMRT = getVarNumeric( "HeatMaxRuntime", 7200, dev)
        local runTime = 0
        local cycleStart = getDeviceState( dev, "cycleStart", dev, 0 )
        if cycleStart > 0 then runTime = now - cycleStart end
        D("checkSensor(): handling %1, runTime=%2, heatSP=%3, coolSP=%4", modeStatus, runTime, heatSP, coolSP)
        if runTime > 3599 then
            -- Show as hours and minutes for 100 minutes and up
            luup.variable_set( MYSID, "CycleTime", string.format("%dh%02dm", math.floor(runTime/3600), math.floor(runTime/60) % 60), dev )
        else
            -- Show minutes
            luup.variable_set( MYSID, "CycleTime", string.format("%dm", math.floor(runTime/60), runTime % 60), dev )
        end
        if modeStatus == "Cooling" and (currentTemp <= coolSP or runTime >= coolMRT) then
            goIdle(dev, modeStatus)
            if currentTemp <= coolSP then
                D("checkSensors() cooling setpoint achieved")
                luup.variable_set( SETPOINT_SID, "SetpointAchieved", "1", dev )
            end
            if runTime >= coolMRT then
                L({level=2,msg="Cooling lockout due to excess runtime (%1>%2)"}, runTime, coolMRT)
                setDeviceState( dev, "devLockout", now + getVarNumeric( "CoolingLockout", 1800, dev ), dev )
            end
        elseif modeStatus == "Heating" and (currentTemp >= heatSP or runTime >= heatMRT) then
            goIdle(dev, modeStatus)
            if currentTemp >= heatSP then
                D("checkSensors() heating setpoint achieved")
                luup.variable_set( SETPOINT_SID, "SetpointAchieved", "1", dev )
            end
            if runTime >= heatMRT then
                L({level=2,msg="Heating lockout due to excess runtime (%1>%2)"}, runTime, heatMRT)
                setDeviceState( dev, "devLockout", now + getVarNumeric( "HeatingLockout", 1800, dev ), dev )
            end
        else
            D("checkSensors() continuing %1", modeStatus)
        end
    else
        D("nothing to do in %1 mode", modeStatus)
    end
    saveDeviceState( dev )
    updateDisplayStatus( dev )
end

-- Transition between states.
local function transition( dev, oldTarget, newTarget )
    D("transition(%1,%2,%3)", dev, oldTarget, newTarget)

    -- See if what we're currently doing is compatible with where we're going.
    local currStatus = luup.variable_get( OPSTATE_SID, "ModeState", dev ) or "Idle"
    D("transition() current ModeState is %1", currStatus)
    if newTarget == "Off" then
        goIdle( dev, currStatus )
        clearTask(dev, "fan")
        fanOff(dev)
        luup.variable_set( OPSTATE_SID, "ModeState", "Off", dev )
    else
        -- Going to auto-changeover from any status is pretty much going to work. Handle other targets.
        if newTarget == "CoolOn" then
            -- Going to cool-only. If currently heating, stop that.
            if currStatus == "Heating" then
                goIdle(dev, currStatus)
            end
        elseif newTarget == "HeatOn" then
            -- Going to heat-only. If currently cooling, stop that.
            if currStatus == "Cooling" then
                goIdle(dev, currStatus)
            end
        end
    end
end

-- Check our controlled devices and make sure they are in the expected state.
-- If not, attempt to bring them around.
local function checkDevice( dev, sid, var, oldVal, newVal )
    D("checkDevices(%1,%2,%3,%4,%5)", dev, sid, var, oldVal, newVal)

end

-- Watch callback handler (real callback is in implementation file).
function handleWatch( tdev, sid, var, oldVal, newVal )
    D("handleWatch(%1,%2,%3,%4,%5)", tdev, sid, var, oldVal, newVal )
    assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
    if sid == FANMODE_SID then
        if var == "Mode" then
            local mode = luup.variable_get(OPMODE_SID, "ModeTarget", tdev ) or "Off"
            local state = luup.variable_get(OPSTATE_SID, "ModeState", tdev) or "Idle"
            if mode == "Off" then
                -- If thermostat is off, regardless of new mode, the fan is off.
                fanAutoOff( tdev )
            elseif newVal == "ContinuousOn" then
                clearTask( tdev, "fan" )
                fanOn( tdev )
            elseif newVal ~= "PeriodicOn" then
                fanAutoOff( tdev )
            end
        elseif var == "FanStatus" then
            updateDisplayStatus( tdev )
        end
    elseif sid == OPMODE_SID and var == "ModeTarget" then
        transition( tdev, oldVal, newVal )
        luup.variable_set( OPMODE_SID, "ModeStatus", newVal, tdev )
        checkSensors(tdev)
    elseif sid == OPSTATE_SID and var == "ModeState" then
        updateDisplayStatus( tdev )
    elseif sid == TEMPSENS_SID then
        -- Check all children, since we don't know which
        for _,child in ipairs( children ) do
            checkSensors( child )
        end
    elseif sid == MYSID then
        if var == "SetpointHeating" then
            -- Blech. I hate this hacked crap. But it's what external UIs have come to expect...
            luup.variable_set( SETPOINT_SID .. "_Heat", "CurrentSetpoint", newVal, tdev )
        elseif var == "SetpointCooling" then
            luup.variable_set( SETPOINT_SID .. "_Cool", "CurrentSetpoint", newVal, tdev )
        end
        local heatSP = getVarNumeric( "SetpointHeating", newVal, tdev, MYSID )
        local coolSP = getVarNumeric( "SetpointCooling", heatSP, tdev, MYSID )
        luup.variable_set( SETPOINT_SID, "AllSetpoints", tostring(heatSP) .. "," .. tostring(coolSP) .. "," .. tostring(mean({heatSP,coolSP},1)), tdev )
        checkSensors( tdev )
    elseif sid == SWITCH_SID then
        L("Device %1 (%2) changed %3 from %4 to %5", tdev, luup.devices[tdev].description, var, oldVal, newVal)
    else
        L("*** Unhandled watch callback for tdev=%1, sid=%2, var=%3 (from %4 to %5)", tdev, sid, var, oldVal, newVal)
    end
end

function actionSetEnergyModeTarget( dev, newMode )
    D("actionSetEnergyModeTarget(%1,%2)", dev, newMode)
    if newMode == nil then return false, "Invalid NewModeTarget" end
    newMode = newMode:lower()
    if newMode == "eco" or newMode == "economy" or newMode == "energysavingsmode" then newMode = EMODE_ECO
    elseif newMode == "normal" or newMode == "comfort" then newMode = EMODE_NORMAL
    else
        -- Emulate the behavior of SmartVT by accepting 0/1 for Eco/Normal respectively.
        newMode = tonumber( newMode, 10 )
        if newMode == nil then return false, "Invalid NewModeTarget"
        elseif newMode ~= 0 then newMode = EMODE_NORMAL
        else newMode = EMODE_ECO
        end
    end
    luup.variable_set( OPMODE_SID, "EnergyModeTarget", newMode, dev )
    if newMode ~= EMODE_ECO then
        luup.variable_set( MYSID, "SetpointHeating", luup.variable_get( MYSID, "NormalHeatingSetpoint", dev ) or sysTemps.default, dev )
        luup.variable_set( MYSID, "SetpointCooling", luup.variable_get( MYSID, "NormalCoolingSetpoint", dev ) or sysTemps.default, dev )
    else
        luup.variable_set( MYSID, "SetpointHeating", luup.variable_get( MYSID, "EcoHeatingSetpoint", dev ) or sysTemps.default, dev )
        luup.variable_set( MYSID, "SetpointCooling", luup.variable_get( MYSID, "EcoCoolingSetpoint", dev ) or sysTemps.default, dev )
    end
    luup.variable_set( OPMODE_SID, "EnergyModeStatus", newMode, dev )
    luup.variable_set( SETPOINT_SID, "SetpointAchieved", "0", dev )
    return true
end

-- Set fan operating mode.
function actionSetFanMode( dev, newMode )
    D("actionSetFanMode(%1,%2)", dev, newMode)
    -- We just change the mode here; the variable trigger does the rest.
    if string.match("Auto:ContinuousOn:PeriodicOn:", newMode .. ":") then
        luup.variable_set( FANMODE_SID, "Mode", newMode, dev )
        return true
    end
    return false
end

-- Action to change current (TemperatureSetpoint1) Application
function actionSetApplication( dev, app )
    if string.match("DualHeatingCooling:Heating:Cooling:", app .. ":") then
        luup.variable_set( SETPOINT_SID, "Application", app, dev )
        return true
    end
    return false
end

-- Save current setpoints for the energy mode
local function saveEnergyModeSetpoints( dev )
    local currEmode = luup.variable_get( OPMODE_SID, "EnergyModeStatus", dev ) or EMODE_NORMAL
    D("saveEnergyModeSetpoints(%1) saving setpoints for energy mode %2", dev, currEmode)
    if currEmode ~= EMODE_ECO then
        luup.variable_set( MYSID, "NormalHeatingSetpoint", luup.variable_get( MYSID, "SetpointHeating", dev), dev )
        luup.variable_set( MYSID, "NormalCoolingSetpoint", luup.variable_get( MYSID, "SetpointCooling", dev), dev )
    else
        luup.variable_set( MYSID, "EcoHeatingSetpoint", luup.variable_get( MYSID, "SetpointHeating", dev), dev )
        luup.variable_set( MYSID, "EcoCoolingSetpoint", luup.variable_get( MYSID, "SetpointCooling", dev), dev )
    end
end

-- Action to change (TemperatureSetpoint1) setpoint.
function actionSetCurrentSetpoint( dev, newSP, whichSP )
    D("actionSetCurrentSetpoint(%1,%2)", dev, newSP)

    newSP = tonumber(newSP, 10)
    if newSP == nil then return end
    newSP = constrain( newSP, sysTemps.minimum, sysTemps.maximum )

    if whichSP == nil then whichSP = luup.variable_get( SETPOINT_SID, "Application", dev ) or "DualHeatingCooling" end

    local modeStatus = luup.variable_get( OPMODE_SID, "ModeTarget", dev ) or "Off"

    -- Note that we are watching SetpointHeating and SetpointCooling, so changes
    -- here will cause the watch callback to trigger and update some other things,
    -- and cause a sensor check (fast reacting to new setpoint).

    local heatSP = getVarNumeric( "SetpointHeating", sysTemps.default, dev, MYSID )
    local coolSP = getVarNumeric( "SetpointCooling", sysTemps.default, dev, MYSID )

    if whichSP == "DualHeatingCooling" then
        luup.variable_set( SETPOINT_SID, "CurrentSetpoint", newSP, dev )
        luup.variable_set( MYSID, "SetpointHeating", newSP, dev )
        luup.variable_set( MYSID, "SetpointCooling", newSP, dev )
    elseif whichSP == "Heating" then
        if modeStatus == "HeatOn" then
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", newSP, dev )
        end
        if newSP > coolSP then
            coolSP = newSP
            luup.variable_set( MYSID, "SetpointCooling", coolSP, dev )
        end
        luup.variable_set( MYSID, "SetpointHeating", newSP, dev )
    elseif whichSP == "Cooling" then
        if modeStatus == "CoolOn" then
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", newSP, dev )
        end
        if newSP < heatSP then
            heatSP = newSP
            luup.variable_set( MYSID, "SetpointHeating", heatSP, dev )
        end
        luup.variable_set( MYSID, "SetpointCooling", newSP, dev )
    end
    saveEnergyModeSetpoints( dev )
    luup.variable_set( SETPOINT_SID, "SetpointAchieved", "0", dev )
end

-- Action for SetModeTarget -- change current operating mode
function actionSetModeTarget( dev, lul_settings )
    D("actionSetModeTarget(%1,%2)", dev, lul_settings)
    if lul_settings.NewHeatSetpoint then
        actionSetCurrentSetpoint( dev, lul_settings.NewHeatSetpoint, "Heating" )
    end
    if lul_settings.NewCoolSetpoint then
        actionSetCurrentSetpoint( dev, lul_settings.NewCoolSetpoint, "Cooling" )
    end
    -- ModeTarget is watched, so that callback is where the work is done.
    luup.variable_set( OPMODE_SID, "ModeTarget", lul_settings.NewModeTarget or "Off", dev )
    return true
end

function actionSetDebug( dev, state )
    D("actionSetDebug(%1,%2)", dev, state)
    if state == 1 or state == "1" or state == true or state == "true" then
        debugMode = true
        MAXEVENTS = 1000
        D("actionSetDebug() debug logging enabled")
    end
end

-- If you're wondering what this is, let me tell you my tale of woe... drop me an email.
function getinfo( tdev )
    local dkjson = require("dkjson") or json
    luup.variable_set( MYSID, "int_el", dkjson.encode(eventList), tdev )
end

local function issKeyVal( k, v, s )
    if s == nil then s = {} end
    s["key"] = tostring(k)
    s["value"] = tostring(v)
    return s
end

local function map( m, v, d )
    if m[v] == nil then return d end
    return m[v]
end

local function getDevice( dev, pdev, v )
    local dkjson = require("dkjson") or json
    if v == nil then v = luup.devices[dev] end
    local devinfo = {
          devNum=dev
        , ['type']=v.device_type
        , description=v.description or ""
        , room=v.room_num or 0
        , udn=v.udn or ""
        , id=v.id
        , ['device_json'] = luup.attr_get( "device_json", dev )
        , ['impl_file'] = luup.attr_get( "impl_file", dev )
        , ['device_file'] = luup.attr_get( "device_file", dev )
        , manufacturer = luup.attr_get( "manufacturer", dev ) or ""
        , model = luup.attr_get( "model", dev ) or ""
    }
    local rc,t,httpStatus,url
    url = isOpenLuup and "http://127.0.0.1:3480" or "http://localhost/port_3480"
    rc,t,httpStatus = luup.inet.wget(url .. "/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json", 15)
    if httpStatus ~= 200 or rc ~= 0 then
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
        return devinfo
    end
    local d = dkjson.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

function requestHandler(lul_request, lul_parameters, lul_outputformat)
    D("requestHandler(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
    local action = lul_parameters['action'] or lul_parameters['command'] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
    if action == "debug" then
        local err,msg,job,args = luup.call_action( MYSID, "SetDebug", { debug=1 }, deviceNum )
        return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args))
    end

    if action:sub( 1, 3 ) == "ISS" then
        -- ImperiHome ISS Standard System API, see http://dev.evertygo.com/api/iss#types
        local dkjson = require('dkjson')
        local path = lul_parameters['path'] or action:sub( 4 ) -- Work even if I'home user forgets &path=
        if path == "/system" then
            return dkjson.encode( { id="AutoVirtualThermostat-" .. luup.pk_accesspoint, apiversion=1 } ), "application/json"
        elseif path == "/rooms" then
            local roomlist = { { id=0, name="No Room" } }
            for rn,rr in pairs( luup.rooms ) do
                table.insert( roomlist, { id=rn, name=rr } )
            end
            return dkjson.encode( { rooms=roomlist } ), "application/json"
        elseif path == "/devices" then
            local devices = {}
            for lnum,ldev in pairs( luup.devices ) do
                if ldev.device_type == MYTYPE then
                    local issinfo = {}
                    table.insert( issinfo, issKeyVal( "curmode", map( { Off="Off",HeatOn="Heat",CoolOn="Cool",AutoChangeOver="Auto"}, luup.variable_get( OPMODE_SID, "ModeTarget", lnum ), "Off" ) ) )
                    table.insert( issinfo, issKeyVal( "curfanmode", map( { Auto="Auto",ContinuousOn="On",PeriodicOn="Periodic" }, luup.variable_get(FANMODE_SID, "Mode", lnum), "Auto" ) ) )
                    table.insert( issinfo, issKeyVal( "curenergymode", map( { Normal="Comfort", EnergySavingsMode="Economy" }, luup.variable_get( OPMODE_SID, "EnergyModeTarget", lnum ), "Normal" ) ) )
                    table.insert( issinfo, issKeyVal( "curtemp", luup.variable_get( TEMPSENS_SID, "CurrentTemperature", lnum ), { unit="°" .. sysTemps.unit } ) )
                    table.insert( issinfo, issKeyVal( "cursetpoint", getVarNumeric( "SetpointHeating", sysTemps.default, lnum, MYSID ) ) )
                    table.insert( issinfo, issKeyVal( "cursetpoint1", getVarNumeric( "SetpointCooling", sysTemps.default, lnum, MYSID ) ) )
                    table.insert( issinfo, issKeyVal( "step", 1 ) )
                    table.insert( issinfo, issKeyVal( "minVal", sysTemps.minimum ) )
                    table.insert( issinfo, issKeyVal( "maxVal", sysTemps.maximum ) )
                    table.insert( issinfo, issKeyVal( "availablemodes", "Off,Heat,Cool,Auto" ) )
                    table.insert( issinfo, issKeyVal( "availablefanmodes", "Auto,On,Periodic" ) )
                    table.insert( issinfo, issKeyVal( "availableenergymodes", "Comfort,Economy" ) )
                    table.insert( issinfo, issKeyVal( "defaultIcon", "https://www.toggledbits.com/assets/avt/vt_mode_auto.png" ) )
                    local dev = { id=tostring(lnum),
                        name=ldev.description or ("#" .. lnum),
                        ["type"]="DevThermostat",
                        params=issinfo }
                    if ldev.room_num ~= nil and ldev.room_num ~= 0 then dev.room = tostring(ldev.room_num) end
                    table.insert( devices, dev )
                end
            end
            return dkjson.encode( { devices=devices } ), "application/json"
        else -- action
            local dev, act, p = string.match( path, "/devices/([^/]+)/action/([^/]+)/*(.*)$" )
            dev = tonumber( dev, 10 )
            if dev ~= nil and act ~= nil then
                act = string.upper( act )
                D("requestHandler() handling action path %1, dev %2, action %3, param %4", path, dev, act, p )
                if act == "SETMODE" then
                    local newMode = map( { OFF="Off",HEAT="HeatOn",COOL="CoolOn",AUTO="AutoChangeOver" }, string.upper( p or "" ) )
                    actionSetModeTarget( dev, newMode )
                elseif act == "SETENERGYMODE" then
                    local newMode = map( { COMFORT="Normal", ECONOMY="EnergySavingsMode" }, string.upper( p or "" ) )
                    actionSetEnergyModeTarget( dev, newMode )
                elseif act == "SETFANMODE" then
                    local newMode = map( { AUTO="Auto", ON="ContinuousOn", PERIODIC="PeriodicOn" }, string.upper( p or "" ) )
                    actionSetFanMode( dev, newMode )
                elseif act == "SETSETPOINT" then
                    local temp = tonumber( p, 10 )
                    if temp ~= nil then
                        actionSetCurrentSetpoint( dev, temp, "Heating" )
                    end
                elseif act == "SETSETPOINT1" then
                    local temp = tonumber( p, 10 )
                    if temp ~= nil then
                        actionSetCurrentSetpoint( dev, temp, "Cooling" )
                    end
                else
                    D("requestHandler(): ISS action %1 not handled, ignored", act)
                end
            else
                D("requestHandler(): ISS malformed action request %1", path)
            end
            return "{}", "application/json"
        end
    end

    if action == "status" then
        local dkjson = require("dkjson")
        if dkjson == nil then return "Missing dkjson library", "text/plain" end
        local st = {
            name=_PLUGIN_NAME,
            version=_PLUGIN_VERSION,
            pluginid=_PLUGIN_ID,
            configversion=_CONFIGVERSION,
            author="Patrick H. Rigney (rigpapa)",
            url=_PLUGIN_URL,
            ['type']=MYTYPE,
            responder=luup.device,
            timestamp=os.time(),
            system = {
                version=luup.version,
                isOpenLuup=isOpenLuup,
                isALTUI=isALTUI,
                units=luup.attr_get( "TemperatureFormat", 0 ),
            },
            devices={}
        }
        for k,v in pairs( luup.devices ) do
            if luup.device_supports_service( MYSID, k ) then
                local devinfo = getDevice( k, luup.device, v ) or {}
                local d = getVarNumeric( "FanDevice", 0, k )
                if d ~= 0 then devinfo.fandevice = getDevice( d, luup.device ) or {} end
                d = getVarNumeric( "HeatingDevice", 0, k )
                if d ~= 0 then devinfo.heatingdevice = getDevice( d, luup.device ) or {} end
                d = getVarNumeric( "CoolingDevice", 0, k )
                if d ~= 0 then devinfo.coolingdevice = getDevice( d, luup.device ) or {} end
                d = split( luup.variable_get( MYSID, "TempSensors", k ) or "", "," )
                local ts = {}
                for _,m in ipairs(d) do
                    table.insert( ts, getDevice( tonumber(m,10) or 0, luup.device ) )
                end
                devinfo.tempsensors = ts

                -- Rigamarole to get instance-specified device data... must be passed through state variables (uck)
                local rc,rs,job,rargs = luup.call_action( MYSID, "getinfo", {}, k )
                if rc == 0 then
                    for rn,rv in pairs(rargs) do
                        devinfo[rn] = json.decode(rv)
                    end
                else
                    devinfo["__comment_getinfo"] = string.format("getinfo action returned %s, %s, %s, %s",
                        tostring(rc), tostring(rs), tostring(job), dump(rargs))
                end
                table.insert( st.devices, devinfo )

                -- Clean up
                luup.variable_set( MYSID, "int_el", "", k )

            end
        end
        return dkjson.encode( st ), "application/json"
    end

    return "<html><head><title>" .. _PLUGIN_NAME .. " Request Handler"
        .. "</title></head><body bgcolor='white'>Request format: <tt>http://" .. (luup.attr_get( "ip", 0 ) or "...")
        .. "/port_3480/data_request?id=lr_" .. lul_request
        .. "&action=...</tt><p>Actions: status<br>debug&device=<i>devicenumber</i><br>ISS"
        .. "<p>Imperihome ISS URL: <tt>...&action=ISS&path=</tt><p>Documentation: <a href='"
        .. _PLUGIN_URL .. "' target='_blank'>" .. _PLUGIN_URL .. "</a></body></html>"
        , "text/html"
end

local function plugin_checkVersion(dev)
    assert(dev ~= nil)
    D("checkVersion() branch %1 major %2 minor %3, string %4, openLuup %5", luup.version_branch, luup.version_major, luup.version_minor, luup.version, isOpenLuup)
    if isOpenLuup then return true end
    if luup.version_branch == 1 and luup.version_major >= 7 then
        local v = luup.variable_get( MYSID, "UI7Check", dev )
        if v == nil then luup.variable_set( MYSID, "UI7Check", "true", dev ) end
        return true
    end
    return false
end

local function plugin_runOnce(dev)
    assert(dev ~= nil)
    local rev = getVarNumeric("Version", 0, dev)
    if (rev == 0) then
        -- Initialize for new installation
        D("runOnce() Performing first-time initialization!")
        luup.variable_set(MYSID, "DebugMode", "0", dev)
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
        return
    end

    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
    end
end

local function child_runOnce( dev, pdev )
    assert(dev ~= nil)
    local rev = getVarNumeric("Version", 0, dev)
    if (rev == 0) then
        -- Initialize for new installation
        D("runOnce() Performing first-time initialization!")
        if luup.attr_get("TemperatureFormat",0) == "C" then
            luup.variable_set( MYSID, "SetpointHeating", "18", dev)
            luup.variable_set( MYSID, "SetpointCooling", "24", dev)
            luup.variable_set( MYSID, "Differential", "1", dev)
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", "18", dev)
            luup.variable_set( SETPOINT_SID .. "_Heat", "CurrentSetpoint", "18", dev)
            luup.variable_set( SETPOINT_SID .. "_Cool", "CurrentSetpoint", "24", dev)
            luup.variable_set( MYSID, "EcoHeatingSetpoint", "13", dev )
            luup.variable_set( MYSID, "EcoCoolingSetpoint", "29", dev )
            luup.variable_set( MYSID, "ConfigurationUnits", "C", dev )
        else
            luup.variable_set( MYSID, "SetpointHeating", "64", dev)
            luup.variable_set( MYSID, "SetpointCooling", "76", dev)
            luup.variable_set( MYSID, "Differential", "1", dev)
            luup.variable_set( SETPOINT_SID, "CurrentSetpoint", "64", dev)
            luup.variable_set( SETPOINT_SID .. "_Heat", "CurrentSetpoint", "64", dev)
            luup.variable_set( SETPOINT_SID .. "_Cool", "CurrentSetpoint", "76", dev)
            luup.variable_set( MYSID, "EcoHeatingSetpoint", "55", dev )
            luup.variable_set( MYSID, "EcoCoolingSetpoint", "85", dev )
            luup.variable_set( MYSID, "ConfigurationUnits", "F", dev )
        end
        luup.variable_set( MYSID, "NormalHeatingSetpoint", luup.variable_get( MYSID, "SetpointHeating", dev ), dev )
        luup.variable_set( MYSID, "NormalCoolingSetpoint", luup.variable_get( MYSID, "SetpointCooling", dev ), dev )
        luup.variable_set(MYSID, "Interval", "60", dev)
        luup.variable_set(MYSID, "EquipmentDelay", "300", dev)
        luup.variable_set(MYSID, "FanOnDelayCooling", "0", dev)
        luup.variable_set(MYSID, "FanOffDelayCooling", "60", dev)
        luup.variable_set(MYSID, "FanOnDelayHeating", "0", dev)
        luup.variable_set(MYSID, "FanOffDelayHeating", "60", dev)
        luup.variable_set(MYSID, "FanCycleMinsPerHr", "15", dev)
        luup.variable_set(MYSID, "CycleTime", "", dev)
        luup.variable_set(MYSID, "HeatMaxRuntime", "7200", dev)
        luup.variable_set(MYSID, "HeatingLockout", "1800", dev)
        luup.variable_set(MYSID, "CoolMaxRuntime", "7200", dev)
        luup.variable_set(MYSID, "CoolingLockout", "1800", dev)
        luup.variable_set(MYSID, "MaxSensorDelay", "3600", dev)
        luup.variable_set(MYSID, "MaxSensorBattery", "7200", dev)
        luup.variable_set(MYSID, "MinBatteryLevel", "1", dev)
        luup.variable_set(MYSID, "TempSensors", "", dev)
        luup.variable_set(MYSID, "CoolingDevice", "0", dev)
        luup.variable_set(MYSID, "HeatingDevice", "0", dev)
        luup.variable_set(MYSID, "FanDevice", "0", dev)
        luup.variable_set(MYSID, "Failure", "1", dev) -- start in failed state (because nothing is configured)
        luup.variable_set(MYSID, "Schedule", "", dev)
        luup.variable_set(MYSID, "DisplayTemperature", "--.-", dev)
        luup.variable_set(MYSID, "DisplayStatus", "Off", dev)

        luup.variable_set(OPMODE_SID, "ModeTarget", "Off", dev)
        luup.variable_set(OPMODE_SID, "ModeStatus", "Off", dev)
        luup.variable_set(OPSTATE_SID, "ModeState", "Off", dev)
        luup.variable_set(OPMODE_SID, "EnergyModeTarget", EMODE_NORMAL, dev)
        luup.variable_set(OPMODE_SID, "EnergyModeStatus", EMODE_NORMAL, dev)

        luup.variable_set(FANMODE_SID, "Mode", "Auto", dev)
        luup.variable_set(FANMODE_SID, "FanStatus", "Off", dev)

        luup.variable_set(SETPOINT_SID, "Application", "DualHeatingCooling", dev)
        luup.variable_set(SETPOINT_SID, "SetpointAchieved", "0", dev)
        luup.variable_set(SETPOINT_SID, "AllSetpoints", "", dev)
        luup.variable_set(SETPOINT_SID, "AutoMode", 0, dev)

        luup.variable_set(HADEVICE_SID, "ModeSetting", "1:;2:;3:;4:", dev)

        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
        return
    end

    -- No matter what happens above, if our versions don't match, force that here/now.
    if (rev ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, dev)
    end
end

local function watchDevice( devVar, tdev )
    D("watchDevice(%1,%2)", devVar, tdev)
    local wd = getVarNumeric( devVar, 0, tdev, MYSID )
    if wd ~= 0 then
        if luup.devices[wd] ~= nil and luup.device_supports_service(SWITCH_SID, wd) then
            luup.variable_watch( "avtWatchCallback", SWITCH_SID, "Status", wd )
        else
            L("%1 %2 does not exist or does not implement SwitchPower1 service", devVar, wd)
        end
    end
end

function child_init( cdev, pdev )
    -- "One time" initializations
    child_runOnce( cdev, pdev )

    -- Other inits
    local units = luup.attr_get("TemperatureFormat", 0)
    if units == "C" then
        -- Default temp 22, range 5 to 35
        sysTemps = { unit="C", default=22, minimum=5, maximum=35 }
    else
        -- Default temp 72, range 41 to 95
        sysTemps = { unit="F", default=72, minimum=41, maximum=95 }
    end
    local cfUnits = luup.variable_get( MYSID, "ConfigurationUnits", cdev )
    if cfUnits ~= units then
        -- If system config doesn't match our config, stop. Potential danger.
        return false, "System temp units changed", _PLUGIN_NAME
    end

    -- Watch some things, to make us quick to respond to changes.
    luup.variable_watch( "avtWatchCallback", MYSID, "SetpointHeating", cdev )
    luup.variable_watch( "avtWatchCallback", MYSID, "SetpointCooling", cdev )
    luup.variable_watch( "avtWatchCallback", OPMODE_SID, "ModeTarget", cdev )
    luup.variable_watch( "avtWatchCallback", OPSTATE_SID, "ModeState", cdev )
    luup.variable_watch( "avtWatchCallback", FANMODE_SID, "Mode", cdev )
    luup.variable_watch( "avtWatchCallback", FANMODE_SID, "FanStatus", cdev )
    local ts = luup.variable_get(MYSID, "TempSensors", cdev) or ""
    local tst = split(ts)
    for _,tx in ipairs(tst) do
        local tnum = tonumber(tx,10) or 0
        if luup.variable_get( TEMPSENS_SID, "CurrentTemperature", tnum ) ~= nil then
            luup.variable_watch( "avtWatchCallback", TEMPSENS_SID, "CurrentTemperature", tnum )
        end
    end
    watchDevice("FanDevice", cdev)
    watchDevice("HeatingDevice", cdev)
    watchDevice("CoolingDevice", cdev)

    -- Make sure devices are doing what we expect for current status. The rest will be
    -- sorted later.
    if not restoreDeviceState( cdev ) then -- attempt to restore device state, save across luup reloads
        L{level=2,msg="Can't reload device state or expired, resetting..."}
        fanAutoOff( cdev )
        goIdle( cdev )
    else
        local tt = luup.variable_get(OPMODE_SID, "ModeTarget", cdev) or "Off"
        local st = luup.variable_get(OPSTATE_SID, "ModeState", cdev) or "Idle"
        if ( tt == "CoolOn" or tt == "AutoChangeOver" ) and st == "Cooling" then
            -- Use low-level funcs so other state/data doesn't get reset
            fanOn( cdev )
            coolOn( cdev )
            luup.variable_set(OPSTATE_SID, "ModeState", "Cooling", cdev)
        elseif ( tt == "HeatOn" or tt == "AutoChangeOver" ) and st == "Heating" then
            -- Use low-level funcs so other state/data doesn't get reset
            fanOn( cdev )
            heatOn( cdev )
            luup.variable_set(OPSTATE_SID, "ModeState", "Heating", cdev)
        else
            -- Off, idle, or not sure. Restore to idle.
            fanAutoOff( cdev )
            goIdle( cdev, st )
        end
    end

    -- Seed the recurring "sense" task.
    scheduleTask( cdev, { ['type']="sense", func=checkSensors, dev=cdev, ['time']=os.time()+30, recurring=getVarNumeric("Interval", 60, cdev) } )
end

function plugin_init(dev)
    D("init(%1)", dev)
    L("starting plugin version %1 device %2", _PLUGIN_VERSION, dev)

    pluginDevice = dev

    if luup.attr_get("subcategory_num", dev) ~= "1" then
        luup.attr_set("subcategory_num", 1, dev)
    end

    -- Check for ALTUI and OpenLuup
    children = {}
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
            local rc,rs,jj,ra
            D("init() detected ALTUI at %1", k)
            isALTUI = true
            rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=MYTYPE,
                    newScriptFile="J_AutoVirtualThermostat1_ALTUI.js",
                    newDeviceDrawFunc="AutoVirtualThermostat_ALTUI.deviceDraw",
                    newControlPanelFunc="AutoVirtualThermostat_ALTUI.controlPanelDraw",
                    newStyleFunc="AutoVirtualThermostat_ALTUI.getStyle"
                }, k )
            D("init() ALTUI's RegisterPlugin action returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra)
        elseif v.device_type == "openLuup" then
            L("Detected openLuup!")
            isOpenLuup = true
        elseif v.device_num_parent == dev then
            table.insert( children, k )
        end
    end

    -- Make sure we're in the right environment
    if not plugin_checkVersion(dev) then
        L{level=1,msg="This plugin does not run on this firmware!"}
        luup.variable_set( MYSID, "Failure", "1", dev )
        luup.variable_set( MYSID, "DisplayStatus", "Unsupported firmware", dev )
        luup.set_failure( 1, dev )
        return false, "Unsupported system firmware", _PLUGIN_NAME
    end

    -- See if we need any one-time inits
    plugin_runOnce(dev)

    -- Initialize device context
    runStamp = 0
    devState = {}
    local dm = getVarNumeric("DebugMode", 0, dev)
    if dm ~= 0 then
        debugMode = true
        if dm > 100 then
            MAXEVENTS = dm
        end
        D("plugin_init() enabled debug by state var, MAXEVENTS=%1", MAXEVENTS)
    end

    -- Create child if we have none.
    if ( #children == 0 ) then
        local ptr = luup.chdev.start( dev );
        luup.chdev.append( dev, ptr, 't1', 'Generic Virtual Thermostat',
            "urn:schemas-upnp-org:device:HVAC_ZoneThermostat:1",
            "D_HVAC_ZoneThermostat1.xml",
            "",
            ",device_json=D_HVAC_ZoneTwoSetPointsThermostat1.json", false )
        luup.chdev.sync( dev, ptr )
    end

    for _,cdev in ipairs( children ) do
        child_init( cdev )
    end

    L("Running!")

    luup.set_failure( 0, dev )
    return true, "OK", _PLUGIN_NAME
end

function getVersion()
    return _PLUGIN_VERSION, _PLUGIN_NAME, _CONFIGVERSION
end
