# Auto Virtual Thermostat #

## Introduction ##

Auto Virtual Thermostat is a plugin for for Vera home automation controllers that mimics the behavior of a standard heating/cooling
thermostat, but uses a separate temperature sensor for its input, and controls switches for its output. It
allows, for example, a space heater and window air conditioner to work like a typical HVAC system. When the
temperature drops below the heating setpoint, the space heater's switch is turned on, until the sensor indicates that
setpoint has been achieved, at which time the heater is turned off. If the temperature goes above the cooling 
setpoint, the cooling unit's switch is turned on until the cooling setpoint is achieved.

Auto Virtual Thermostat has been tested on openLuup with AltUI.

Auto Virtual Thermostat is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://forum.micasaverde.com/index.php/topic,54232.0.html).

Please consider supporting AVT and my other projects by making
[a small donation](https://www.toggledbits.com/donate).

For more information, see <http://www.toggledbits.com/avt/>.

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.
There is also active discussion and support available via the [AVT topic on the Vera forums](http://forum.micasaverde.com/index.php/topic,54232.0.html).

## License ##

AVT is offered under GPL (the GNU Public License) 3.0. See the LICENSE file for details.

## Disclaimer ##

Auto Virtual Thermostat (AVT) is intended for controlling devices that are supervised by human operators only; it is not
intended for unattended operation at any time. The failure modes of the Vera the devices used with it are too
many and too complex, and in many cases it is not even possible for AVT to be aware of failures, or make
an effective, safe response to a failure. Use of AVT is therefore entirely at your own risk.
