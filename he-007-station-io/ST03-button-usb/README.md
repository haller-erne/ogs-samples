# ST03-usb-button

This OGS sample project shows how to connect an USB dome button to OGS. This
does not really fit into the _station IO_ context, but as the other samples
also show how to connect external acknowledge buttons, it is nevertheless
included here (even though there is no `station_io.lua`).

The dome button used is and USB-RGBKey (see [https://www.haller-erne.de/he/usb-rgbkey](https://www.haller-erne.de/he/usb-rgbkey)), here is a picture:
![usb dome button](usb_domebutton.png)

## Overall setup

The overall setup of this sample can be seen in the `config.lua` file. Basically the
following modules are loaded:

- import_config: Helper module to automatically import the configuration
- barcode, user_manager: default modules for barcode handling and user-rights
- usb_button: (Standard) code to communicate with the USB dome button over the custom HID protocol

The `../shared/usb_button.lua` automatically registers the OGS key press handler (i.e. when the key-input tool is active). While the OGS key-input
tool is active, the LUA function `GetOperationResultByKeyInput()` is called. Depending on
the return value, OGS records no key press, an OK button key press or a NOK button key press.

The function implementation for `GetOperationResultByKeyInput()` in `usb_button.lua` actually
only checks the state of the Button (as reported by the HID communication)

## Station.ini configuration

There is no configuration needed in `station.ini`. The `usb_button.lua` code
checks for USB devices with the known USB vendor- and device-ID for the USB
dome button and connects to it to echange data.

Notes:

- The sample code only supports a single dome button
- Some default blink patterns are generated:

  - Tool not active: slowly rotating blue blink pattern
  - Tool active, waiting for a button press: Glowing violet color
  - Tool pressed: green color

## Running a test

For a quick test, use any workflow where a `key input` tool is used.
The configuration database contains a sample workflow `T-31`, where only a `key input` tool is
defined (start it by entering the model code `T-31` and any 10-digit serial number).

## Use with other buttons or HID devices

The code to implement the button behaviour uses the `luahid` module, which wraps the open source `hidapi.dll` - see the [LuaHID documentation](https://haller-erne.github.io/ogs/libs/lua-hid/).

The library supports all types of HID devices (but not keyboards and mice), so it can be used to
integrate other USB HID devices into OGS.
