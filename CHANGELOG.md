# Change Log #

## Version 1.6 (develop branch) ##

* Upgrade detection of AltUI so we don't falsely detect when bridged (on "real" device triggers AltUI feature registration).
* Implement AllSetpoints state variable, for user convenience. 
* openLuup loads modules differently from Vera Luup, so work out how to get AVT working on openLuup when multiple device instances are created (differences don't matter if only one device).

## Version 1.5 (released) ##

* Change image URLs to meet new asset location.

## Version 1.4 (released) ##

* Improve status feedback (for me) by adding event tracing to the status report.
* Debugging and help links on configuration age.
* Check CommFailure on temp sensors.
* Move UI buttons for improved appearance.
* Track to Vera's odd/broken model for state variables for separate heating and cooling setpoints.

## Version 1.3 (released) ##

* Formal release incorporating fixes for issue #4, handling of MinBatteryLevel.

## Version 1.2.1 (hotfix)

* Fix problem with MinBatteryLevel setting (upgrade 1.2 to 1.2.1, or work around by setting MinBatteryLevel=0).

## Version 1.2 (released)

* ImperiHome ISS API support
* Full UI and Comfort/Economy switching on ALTUI (thank you amg0 for your support)
* Uses newer Vera spinner_horizontal controls in UI7. These work better and more consistently, and also allow the temperature to be edited directly (click on the displayed setpoint and enter a new setpoint).
* Tighten checks around battery-operated thermostats, and introduce new MinBatteryLevel state variable to set the minimum acceptable battery level. Previously this could not be controlled, and it was assumed that any recent thermostat report meant that the battery was OK, but some devices drift unacceptably in their temperature measurements as battery capacity drops, so this adds a way for the user to specify a level at which it may become unacceptable. The default is 1, and the units are percent (that is, a full battery reports 100).

## Version 1.1 (released) ##

* Add Comfort/Economy mode switching (user-directed) with separate setpoints.
* Minor bug fixes.
* Use HTTPS for icon URLs.
* Link for donations.

## Version 1.0 (released) ##

* Initial public release.
