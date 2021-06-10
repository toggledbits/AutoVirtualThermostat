//# sourceURL=J_AutoVirtualThermostat1_UI7.js
/**
 * J_AutoVirtualThermostat1_UI7.js
 * Configuration interface for Virtual Thermostat
 *
 * Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved.
 * This file is part of the Auto Virtual Thermostat Plugin for Vera.
 * For license information, see LICENSE at https://github.com/toggledbits/avt/
 */
/* globals api,jQuery */

// "use strict"; // fails under UI7, fine on ALTUI
var AutoVirtualThermostat = (function(api) {

    // unique identifier for this plugin...
    var uuid = '32f7fe60-79f5-11e7-969f-74d4351650de';

    var serviceId = "urn:toggledbits-com:serviceId:AutoVirtualThermostat1";

    var myModule = {};

    function onBeforeCpanelClose(args) {
        /* Get the target mode and send it back. This makes VT re-evaluate its settings. */
        var devid = api.getCpanelDeviceId();
        var mode = api.getDeviceState( devid, "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeTarget" );
        api.performActionOnDevice( devid, "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "SetModeTarget", { NewTargetMode: mode } );
    }

    function initPlugin() {
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }

    function updateSelectedSensors() {
        var myDevice = api.getCpanelDeviceId();
        var slist = [];
        jQuery('select.tempsensor').each( function( ix, obj ) {
            var devId = jQuery(obj).val();
            if (devId != "")
                slist.push( devId );
        });
        api.setDeviceStatePersistent( myDevice, serviceId, "TempSensors", slist.join(","), 0);
    }

    function updateSchedule() {
        var myDevice = api.getCpanelDeviceId();
        var schedStart = jQuery("select#schedStart").val();
        var schedEnd = jQuery("select#schedEnd").val();
        if ( ""==schedStart ) {
            api.setDeviceStatePersistent(myDevice, serviceId, "Schedule", "", 0);
        } else {
            schedStart = parseInt(schedStart) * 60;
            var m = jQuery("select#schedStart-min").val();
            if ( ""!=m )
                schedStart += parseInt(m);
            if ( ""==schedEnd )
                schedEnd = 0;
            else
                schedEnd = parseInt(schedEnd) * 60;
            m = jQuery("select#schedEnd-min").val();
            if ( ""!=m )
                schedEnd += parseInt(m);
            api.setDeviceStatePersistent(myDevice, serviceId, "Schedule", schedStart + "-" + schedEnd, 0);
        }
    }

    function timeSelector( elemId ) {
        var html = '<select class="tbselhour" id="' + elemId + '"><option value=""></option>';
        for (var i=0; i<24; ++i) html += '<option value="' + i + '">' + (i < 10 ? "0" + i : i) + '</option>';
        html += '</select>';
        html += '&nbsp;:&nbsp;';
        html += '<select class="tbselmin" id="' + elemId + '-min"><option value=""></option>';
        for (var i=0; i<59; i+=5) html += '<option value="' + i + '">' + (i < 10 ? "0" + i : i) + '</option>';
        html += '</select>';
        return html;
    }

    function deviceOptions( lbl, elemId, rooms, filterFunc ) {
        var myDevice = api.getCpanelDeviceId();
        var html = '<div>';
        html += '<label class="col-xs-2" for="' + elemId + '">' + lbl + '</label> ';
        html += '<select id="' + elemId + '"><option value="">(none/not used)</option>';
        rooms.forEach( function(room) {
            var first = true;
            if (room.devices) {
                room.devices.forEach( function(dev) {
                    if ( dev.id != myDevice && filterFunc( dev.id, dev ) ) {
                        if (first)
                            html += "<option disabled>--" + room.name + "--</option>";
                        first = false;
                        html += '<option value="' + dev.id + '">' + dev.friendlyName + '</option>';
                    }
                });
            }
        });
        html += '</select>';
        html += '</div>';
        return html;
    }

    function configurePlugin()
    {
        if ( true ) {
            api.setCpanelContent('<h4>There is no UI for this version/branch</h4>');
            return;
        }

        try {
            initPlugin();

            var myDevice = api.getCpanelDeviceId();

            var i, j, html = "";

            html += "<style>";
            html += ".tb-about { margin-top: 24px; }";
            html += ".color-green { color: #00a652; }";
            html += '.tb-begging { margin-top: 12px; color: #ff6600; }';
            html += '.tb-links { margin-top: 12px; font-size: 0.8em; }';
            html += "</style>";
            html += '<link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">';

            // Make our own list of devices, sorted by room.
            var devices = api.cloneObject( api.getListOfDevices() );
            var noroom = { "id": 0, "name": "No Room", "devices": [] };
            var rooms = [ noroom ];
            var roomIx = {};
            roomIx[String(noroom.id)] = noroom;
            var dd = devices.sort( function( a, b ) {
                if ( a.id == myDevice ) return -1;
                if ( b.id == myDevice ) return 1;
                if ( a.name.toLowerCase() === b.name.toLowerCase() ) {
                    return a.id < b.id ? -1 : 1;
                }
                return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1;
            });
            for (i=0; i<dd.length; i+=1) {
                var devobj = api.cloneObject( dd[i] );
                devobj.friendlyName = "#" + devobj.id + " " + devobj.name;
                var roomid = devobj.room || 0;
                var roomObj = roomIx[String(roomid)];
                if ( roomObj === undefined ) {
                    roomObj = api.cloneObject( api.getRoomObject( roomid ) );
                    roomObj.devices = [];
                    roomIx[String(roomid)] = roomObj;
                    rooms[rooms.length] = roomObj;
                }
                roomObj.devices.push( devobj );
            }
            r = rooms.sort(
                // Special sort for room name -- sorts "No Room" last
                function (a, b) {
                    if (a.id === 0) return 1;
                    if (b.id === 0) return -1;
                    if (a.name === b.name) return 0;
                    return a.name > b.name ? 1 : -1;
                }
            );

            // Sensor
            html += '<div id="sensorgroup">';
            html += '<div class="sensorrow">';
            html += '<label class="col-xs-2" for="sensor1">Temperature Sensor:</label> ';
            html += '<select class="tempsensor" id="sensor1"><option value="">--choose--</option>';
            r.forEach( function( roomObj ) {
                if ( roomObj.devices && roomObj.devices.length ) {
                    var first = true;
                    for (j=0; j<roomObj.devices.length; ++j) {
                        var devid = roomObj.devices[j].id;
                        if (devid == myDevice) continue; // don't allow self-reference
                        var st = api.getDeviceState( devid, "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature" );
                        if (st) {
                            if (first)
                                html += "<option disabled>--" + roomObj.name + "--</option>";
                            first = false;
                            html += '<option value="' + devid + '">' + roomObj.devices[j].friendlyName + '</option>';
                        }
                    }
                }
            });
            html += '</select>';
            html += '&nbsp;<i class="material-icons w3-large color-green cursor-hand" id="addsensorbtn">add_circle_outline</i>';
            html += "</div>"; // sensorrow
            html += '</div>'; // sensorgroup

            // Heating Device
            html += '<div class="clearfix"></div>';
            html += deviceOptions('Heating Device:', 'hdevice', rooms, function( id, dev ) {
                var st = api.getDeviceState( id, "urn:upnp-org:serviceId:SwitchPower1", "Status" );
                return st !== false;
            });

            // Cooling Device
            html += '<div class="clearfix"></div>';
            html += deviceOptions('Cooling Device:', 'cdevice', rooms, function( id, dev ) {
                var st = api.getDeviceState( id, "urn:upnp-org:serviceId:SwitchPower1", "Status" );
                return st !== false;
            });

            // Fan Device
            html += '<div class="clearfix"></div>';
            html += deviceOptions('Fan Device:', 'fdevice', rooms, function( id, dev ) {
                var st = api.getDeviceState( id, "urn:upnp-org:serviceId:SwitchPower1", "Status" );
                return st !== false;
            });

            // Schedule
            html += '<div class="clearfix"></div>';
            html += '<div>';
            html += '<label class="col-xs-2">Schedule:</label>';
            html += timeSelector('schedStart');
            html += '&nbsp;to&nbsp;';
            html += timeSelector('schedEnd');
            html += '</div>';

            html += '<div class="clearfix"></div><div><br/><b>IMPORTANT!</b> After changing device configuration, it is required that you <a href="http://';
            html += '/port_3480/data_request?id=reload&r=' + Math.random() + '" target="_blank">reload Luup</a> for your changes to take effect.</div>';

            html += '<div class="clearfix"></div>';
            html += '<div class="tb-about">Auto Virtual Thermostat ver 1.6develop &#169; 2017,2018 Patrick H. Rigney, All Rights Reserved.<br/>';
            html += 'For documentation, support, and license information, please see <a href="http://www.toggledbits.com/avt/" target="_blank">http://www.toggledbits.com/avt/</a>';
            html += ' Your continued use of this software constitutes acceptance of and agreement to the terms of the license without limitation or exclusion.';
            html += ' CAUTION! This plugin is not to be used to control unattended devices!';
            html += '<p class="tb-begging"><b>Find Auto Virtual Thermostat useful?</b> Please consider a <a target="_blank" href="https://www.toggledbits.com/donate">a small donation</a>, to support my continuing work on this and other plugins. I am grateful for any amount you choose to give!</p>';
            html += '</div>';

            html += '<div class="tb-links">Tech Support links: <a target="_blank" href="/port_3480/data_request?id=variableset&serviceId=urn:toggledbits-com:serviceId:AutoVirtualThermostat1&DeviceNum='
                + myDevice + '&Variable=DebugMode&Value=1000">Debug ON</a>';
            html += ' &#149; <a target="_blank" href="/port_3480/data_request?id=reload">Reload Luup</a>';
            html += ' &#149; <a target="_blank" href="/port_3480/data_request?id=lr_AutoVirtualThermostat&action=status">Status Data</a>';
            html += ' &#149; <a target="_blank" href="/port_3480/data_request?id=variableset&serviceId=urn:toggledbits-com:serviceId:AutoVirtualThermostat1&DeviceNum='
                + myDevice + '&Variable=DebugMode&Value=">Debug OFF</a>';
            html += '</div>';

            // Push generated HTML to page
            api.setCpanelContent(html);

            // Restore values
            var s;
            s = api.getDeviceState(myDevice, serviceId, "TempSensors") || "";
            var t = s.split(',');
            if ( t.length > 0 ) {
                jQuery("select#sensor1").val(t.shift());
                var ix = 1;
                t.forEach( function( v ) {
                    ix = ix + 1;
                    var newId = "sensor" + ix;
                    jQuery('div#sensorgroup').append('<div class="sensorrow clearfix"><label class="col-xs-2" for="' + newId
                        + '">&nbsp;</label><select class="tempsensor" id="' + newId + '"></select></div>');
                    jQuery('select#' + newId).append(jQuery('select#sensor1 option').clone());
                    jQuery('select#' + newId).val(v);
                });
            }
            jQuery("select.tempsensor").change( updateSelectedSensors );
            jQuery("i#addsensorbtn").click( function( ) {
                var lastId = jQuery("div.sensorrow:last select").attr("id");
                var ix = parseInt(lastId.substr(6)) + 1;
                var newId = "sensor" + ix;
                jQuery('div#sensorgroup').append('<div class="sensorrow clearfix"><label class="col-xs-2" for="' + newId
                    + '">&nbsp;</label><select class="tempsensor" id="' + newId + '"></select></div>');
                jQuery('select#' + newId).append(jQuery('select#sensor1 option').clone()).change( updateSelectedSensors );
            });

            s = api.getDeviceState(myDevice, serviceId, "FanDevice");
            jQuery("select#fdevice").val(s ? s : "").change( function( obj ) {
                var newVal = jQuery(this).val();
                api.setDeviceStatePersistent(myDevice, serviceId, "FanDevice", newVal, 0);
            });

            s = api.getDeviceState(myDevice, serviceId, "CoolingDevice");
            jQuery("select#cdevice").val(s ? s : "").change( function( obj ) {
                var newVal = jQuery(this).val();
                api.setDeviceStatePersistent(myDevice, serviceId, "CoolingDevice", newVal, 0);
            });

            s = api.getDeviceState(myDevice, serviceId, "HeatingDevice");
            jQuery("select#hdevice").val(s ? s : "").change( function( obj ) {
                var newVal = jQuery(this).val();
                api.setDeviceStatePersistent(myDevice, serviceId, "HeatingDevice", newVal, 0);
            });

            s = api.getDeviceState(myDevice, serviceId, "Schedule");
            if (s) {
                var t = s.split("-");
                var restoreTime = function ( elemId, val ) {
                    var hh = Math.floor(val / 60);
                    var mm = val % 60;
                    jQuery("select#" + elemId).val(hh);
                    jQuery("select#" + elemId + "-min").val(mm);
                };
                restoreTime( "schedStart", t[0] );
                restoreTime( "schedEnd", t[1] );
            }
            jQuery('select.tbselhour').change( function( obj ) {
                var id = jQuery(this).attr("id");
                var newVal = jQuery(this).val();
                if ( ""==newVal ) {
                    jQuery("select#" + id + "-min").val("");
                    if ( "schedStart" == id ) {
                        jQuery("select#schedEnd-min").val("");
                        jQuery("select#schedEnd").val("");
                    } else {
                        jQuery("select#schedStart-min").val("");
                        jQuery("select#schedStart").val("");
                    }
                } else {
                    if ( ""==jQuery("select#" + id + "-min").val() )
                        jQuery("select#" + id + "-min").val("0");
                    var losOtro = "select#" + ("schedStart"==id ? "schedEnd" : "schedStart");
                    if ( ""==jQuery(losOtro).val() ) {
                        jQuery(losOtro).val("0");
                        jQuery(losOtro+"-min").val("0");
                    }
                }
                updateSchedule();
            });
            jQuery('select.tbselmin').change( updateSchedule );
        }
        catch (e)
        {
            console.log(e);
            Utils.logError('Error in AutoVirtualThermostat.configurePlugin(): ' + e);
        }
    }

    myModule = {
        uuid: uuid,
        initPlugin: initPlugin,
        onBeforeCpanelClose: onBeforeCpanelClose,
        configurePlugin: configurePlugin
    };
    return myModule;
})(api);
