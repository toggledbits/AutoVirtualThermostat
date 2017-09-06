//# sourceURL=J_VirtualThermostat1_ALTUI.js
"use strict";

var VirtualThermostat_ALTUI = ( function( window, undefined ) {

        function _draw( device ) {
                var html ="";
                var w = MultiBox.getWeatherSettings();
                var s;
                s = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:VirtualThermostat1", "DisplayTemperature");
                html += s;
                s = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:VirtualThermostat1", "DisplayStatus");
                if ( "Cooling" == s || "Heating" == s ) {
                    var t = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:VirtualThermostat1", "CycleTime" );
                    s = s + " " + t;
                }
                html += '<div>' + s + '</div>';
                return html;
        }
    return {
        DeviceDraw: _draw,
    };
})( window );
