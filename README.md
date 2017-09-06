# Virtual Thermostat #

## Introduction ##

Virtual Thermostat is a plugin for for Vera home automation controllers that mimics the behavior of a standard heating/cooling
thermostat, but uses a separate temperature sensor for its input, and controls switches for its output. It
allows, for example, a space heater and window air conditioner to work like a typical HVAC system. When the
temperature drops below the heating setpoint, the space heater's switch is turned on, until the sensor indicates that
setpoint has been achieved, at which time the heater is turned off. If the temperature goes above the cooling 
setpoint, the cooling unit's switch is turned on until the cooling setpoint is achieved.

Virtual Thermostat has been tested on openLuup with AltUI.

Virtual Thermostat is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://http://forum.micasaverde.com/).

For more information, see <http://www.toggledbits.com/vt/>.

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

## License ##

SiteSensor is offered under GPL (the GNU Public License) 3.0. See the LICENSE file for details.
