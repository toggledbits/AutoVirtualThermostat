//# sourceURL=J_AutoVirtualThermostat1_ALTUI.js
"use strict";

var AutoVirtualThermostat_ALTUI = ( function( window, undefined ) {

    function _getStyle() {
        var style = "";
        style += ".avt-container { }";
        style += '.avt-container .row { padding-top: 1px; padding-bottom: 1px; margin-top: 0px; margin-bottom: 0px; }';
        style += '.avt-center { text-align: center; }';
        style += '.avt-status { font-size: 14px; }';
        return style;
    }

    function _drawDevice( device ) {
            var html ="";
            var s;
            s = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "DisplayTemperature");
            html += s;
            s = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "DisplayStatus");
            if ( "Cooling" == s || "Heating" == s ) {
                var t = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "CycleTime" );
                s = s + " " + t;
            }
            html += '<div>' + s + '</div>';
            return html;
    }

    function _drawControlPanel( device, domparent ) {
        var devices = MultiBox.getDevicesSync();
        var controller = MultiBox.controllerOf(device.altuiid).controller;

        function _button(altuiid, colorclass, glyph, service, action, name, value, incr) {
            return ("<button type='button' style='width:50%; padding:0px !important;' class='altui-heater-btn avt-setpointcontrol-{0} {7} btn btn-light btn-sm' data-service='{2}' data-action='{3}' data-name='{4}' data-value='{5}' data-incr='{6}'>{1}</button>".format(
                    altuiid,        // id
                    glyph,  // label
                    service,
                    action,
                    name,
                    value,
                    incr,
                    colorclass
                )
            );
        }

        var glyphTemplate = '<i class="fa fa-{0} {2}" aria-hidden="true" title="{1}"></i>';
        var upArrow = glyphTemplate.format( "arrow-up", "", "" );
        var downArrow = glyphTemplate.format( "arrow-down", "", "" );

        var userOperatingMode1Items = [
            {label:"Off", value:"Off" , service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetModeTarget", name:"NewModeTarget" },
            {label:"Auto", value:"AutoChangeOver" , service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetModeTarget", name:"NewModeTarget"},
            {label:"Cool", value:"CoolOn" , service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetModeTarget", name:"NewModeTarget"},
            {label:"Heat", value:"HeatOn", service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetModeTarget", name:"NewModeTarget"}
        ];
        var userHVACFanOperatingMode1Items = [
            {label:"Auto", value:"Auto", service:"urn:upnp-org:serviceId:HVAC_FanOperatingMode1", action:"SetMode" , name:"NewMode"},
            {label:"On", value:"ContinuousOn", service:"urn:upnp-org:serviceId:HVAC_FanOperatingMode1", action:"SetMode", name:"NewMode"},
            {label:"Cycle", value:"PeriodicOn", service:"urn:upnp-org:serviceId:HVAC_FanOperatingMode1", action:"SetMode", name:"NewMode"}
        ];
        var energyModeItems = [
            {label:"Comfort", value:"Normal", service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetEnergyModeTarget" , name:"NewModeTarget"},
            {label:"Economy", value:"EnergySavingsMode", service:"urn:upnp-org:serviceId:HVAC_UserOperatingMode1", action:"SetEnergyModeTarget", name:"NewModeTarget"}
        ];
        var HVAC_INCREMENT = 0.5;
        var modeTarget = MultiBox.getStatus( device, 'urn:upnp-org:serviceId:HVAC_UserOperatingMode1', 'ModeTarget' );
        var modeEnergy = MultiBox.getStatus( device, 'urn:upnp-org:serviceId:HVAC_UserOperatingMode1', 'EnergyModeTarget' );
        var modeFan = MultiBox.getStatus( device, 'urn:upnp-org:serviceId:HVAC_FanOperatingMode1', 'Mode' );
        var curTemp = MultiBox.getStatus( device, 'urn:upnp-org:serviceId:TemperatureSensor1', 'CurrentTemperature' );
        var heatsetpoint_current = MultiBox.getStatus( device, 'urn:toggledbits-com:serviceId:AutoVirtualThermostat1', 'SetpointHeating' );
        var coldsetpoint_current = MultiBox.getStatus( device, 'urn:toggledbits-com:serviceId:AutoVirtualThermostat1', 'SetpointCooling' );
        var displayStatus = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "DisplayStatus" );
        var failure = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "Failure" );
        var tempUnits = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:AutoVirtualThermostat1", "ConfigurationUnits" );

        var html = "";
        html += "<div id='avt-" + device.altuiid + "' class='avt-container'>";
            html += "<div class='row'>";
                html += "<div class='col-12 col-sm-12 col-lg-2 col-xl-1 avt-center'>";
                    html += ("<span id='avt-currenttemperature-"+device.altuiid+"' class='altui-temperature' >"+((curTemp!=null) ? (parseFloat(curTemp).toFixed(1)) : "--.-") +"&deg;" + tempUnits + "</span>");
                html += "</div>";
                html += "<div class='col-6 col-sm-6 col-lg-2 col-xl-1 avt-center'>";
                    html += ("<span id='avt-heatsetpoint-"+device.altuiid+"' class='altui-temperature altui-red' >"+((heatsetpoint_current!=null) ? (parseFloat(heatsetpoint_current).toFixed(1)) : "--") +"&deg;</span>");
                html += "</div>";
                html += "<div class='col-6 col-sm-6 col-lg-2 col-xl-1 avt-center'>";
                    html += ("<span id='avt-coldsetpoint-"+device.altuiid+"' class='altui-temperature altui-blue' >"+((coldsetpoint_current!=null) ? (parseFloat(coldsetpoint_current).toFixed(1)) : "--") +"&deg;</span>");
                html += "</div>";
            html += "</div>";
            html += "<div class='row'>";
                html += "<div class='col-12 col-sm-12 col-lg-2 col-xl-1'>";
                    if (userOperatingMode1Items.length>0) {
                        html +="<select id='avt-mode-select-{0}' class='altui-heater-select form-control form-control-sm'>".format(device.altuiid);
                        $.each(userOperatingMode1Items, function(idx,item) {
                            html += "<option data-service='{1}' data-action='{2}' data-name='{3}' data-value='{4}' {5}>{0}</option>".format(
                                item.label,item.service,item.action,item.name,item.value,
                                item.value==modeTarget ? 'selected' : '');
                        });
                        html +="</select>";
                    }
                html += "</div>";
                html += "<div class='col-6 col-sm-6 col-lg-2 col-xl-1 avt-center'>";
                        html += _button(device.altuiid, "altui-red", upArrow,
                                    "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat",
                                    "SetCurrentSetpoint",
                                    "NewCurrentSetpoint",
                                    "avt-heatsetpoint-"+device.altuiid,
                                    HVAC_INCREMENT
                                );
                        html += _button(device.altuiid, "altui-red", downArrow,
                                    "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat",
                                    "SetCurrentSetpoint",
                                    "NewCurrentSetpoint",
                                    "avt-heatsetpoint-"+device.altuiid,
                                    -HVAC_INCREMENT
                                );
                html += "</div>";
                html += "<div class='col-6 col-sm-6 col-lg-2 col-xl-1 avt-center'>";
                            html += _button(device.altuiid, "altui-blue", upArrow,
                                        "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool",
                                        "SetCurrentSetpoint",
                                        "NewCurrentSetpoint",
                                        "avt-coldsetpoint-"+device.altuiid,
                                        HVAC_INCREMENT
                                    );
                            html += _button(device.altuiid, "altui-blue", downArrow,
                                        "urn:upnp-org:serviceId:TemperatureSetpoint1_Cool",
                                        "SetCurrentSetpoint",
                                        "NewCurrentSetpoint",
                                        "avt-coldsetpoint-"+device.altuiid,
                                        -HVAC_INCREMENT
                                    );
                html += "</div>";
                html += "<div class='col-12 col-sm-12 col-lg-1 col-xl-1'>";
                    if (userHVACFanOperatingMode1Items.length>0) {
                        html +="<select id='avt-fanmode-select-{0}' class='altui-heater-select form-control form-control-sm'>".format(device.altuiid);
                        $.each(userHVACFanOperatingMode1Items, function(idx,item) {
                            html += "<option data-service='{1}' data-action='{2}' data-name='{3}' data-value='{4}' {5}>{0}</option>".format(
                                item.label,item.service,item.action,item.name,item.value,
                                item.value==modeFan ? 'selected' : '');
                        });
                        html +="</select>";
                    }
                html += "</div>";
            html += "</div>";
            html += "<div class='row'>";
                html += "<div class='col-12 col-sm-12 col-lg-1 col-xl-1'>";
                    if (energyModeItems.length>0) {
                        html +="<select id='avt-energy-select-{0}' class='altui-heater-select form-control form-control-sm'>".format(device.altuiid);
                        $.each(energyModeItems, function(idx,item) {
                            html += "<option data-service='{1}' data-action='{2}' data-name='{3}' data-value='{4}' {5}>{0}</option>".format(
                                item.label,item.service,item.action,item.name,item.value,
                                item.value==modeEnergy ? 'selected' : '');
                        });
                        html +="</select>";
                    }
                html += "</div>";
            html += "</div>";
            html += "<div class='row'>";
                html += "<div class='col-12 col-sm-12 col-lg-4 col-xl-4 avt-status' id='avt-status-{0}'>".format( device.altuiid );
                html += displayStatus;
                if ( failure != "0" ) html += " (AVT inoperative--sensor failure)";
                html += "</div>";
            html += "</div>";
            html += "<div class='row'>";
                html += "<div class='col-12 col-sm-12'>";
                html += '<b>Find AutoVirtualThermostat useful?</b> Please consider supporting the project with <a href="https://www.toggledbits.com/donate" target="_blank">a one-time &ldquo;tip&rdquo;, or a monthly US$1 donation</a>. I am grateful for any support you choose to give!<br/>&nbsp;<br/>Auto Virtual Thermostat ver 1.6stable-181120 &#169; 2017,2018 Patrick H. Rigney, All Rights Reserved. For documentation, support, and license information, please see <a href="https://www.toggledbits.com/avt/" target="_blank">https://www.toggledbits.com/avt/</a> Your continued use of this software constitutes acceptance of and agreement to the terms of the license without limitation or exclusion. CAUTION! This plugin is not to be used to control unattended devices!';
                html += "</div>";
            html += "</div>";
        html += "</div>";

        var cls = 'button.avt-setpointcontrol-{0}'.format(device.altuiid);

        $(".altui-mainpanel").off('click',cls)
            .on('click',cls,device.altuiid,function(event) {
                var selected = $(this);
                var service = $(selected).data('service');
                var action = $(selected).data('action');
                var name = $(selected).data('name');
                var value = parseFloat($('#'+$(selected).data('value')).text());
                var incr = $(selected).data('incr');
                $('#'+$(selected).data('value')).html( (value+incr).toFixed(1)+'&deg;');
                function doItNow(obj) {
                    var params = {}; params[obj.name]=obj.value;
                    MultiBox.runActionByAltuiID(obj.altuiid, obj.service, obj.action, params);
                    // console.log("timer doItNow() :" + JSON.stringify(obj));
                    $(obj.button).data("timer",null);
                }
                var timer = $(this).data("timer");
                if (timer!=undefined) {
                    clearTimeout(timer);
                    // console.log("clear Timeout({0})".format(timer));
                }
                timer = setTimeout(doItNow,1500,{
                        button: $(this),
                        altuiid: event.data,
                        name: name,
                        service: service,
                        action: action,
                        value : value+incr
                });
                // console.log("set Timeout({0})  params:{1}".format(timer,value+incr));
                $(this).data("timer",timer);
            }
        );
        html += "<script type='text/javascript'>";
        html += " $('div#avt-" + device.altuiid + " select.altui-heater-select').on('change', function() {      ".format(device.altuiid);
        html += "   var selected = $(this).find(':selected');                   ";
        html += "   var service = $(selected).data('service');                  ";
        html += "   var action = $(selected).data('action');                    ";
        html += "   var name = $(selected).data('name');                    ";
        html += "   var value = $(selected).data('value');                  ";
        html += "   var params = {}; params[name]=value;                ";
        html += "   MultiBox.runActionByAltuiID('{0}', service, action, params);".format(device.altuiid);
        html += "});";
        html += "</script>";

        $(domparent).append(html);

        // interactions
        if ( failure != "0" ) {
            $("#avt-currenttemperature-"+device.altuiid).addClass("altui-red");
            $("#avt-status-"+device.altuiid).addClass("altui-red");
        } else {
            $("#avt-currenttemperature-"+device.altuiid).removeClass("altui-red");
            $("#avt-status-"+device.altuiid).removeClass("altui-red");
        }
    }

    return {
        getStyle : _getStyle,
        deviceDraw: _drawDevice,
        controlPanelDraw: _drawControlPanel
    };
})( window );
