# An intelligent device

This application uses the [device_bot](https://github.com/floitsch/toit-device-bot)
package to give an ESP32 some intelligence.

In the video below, OpenAI simply gets the description for how to control
  the LEDs.

```toit
class Leds:
  pin_green_/gpio.Pin
  pin_red_/gpio.Pin

  constructor:
    pin_green_ = gpio.Pin LED_GREEN_PIN --output
    pin_red_ = gpio.Pin LED_RED_PIN --output

  close:
    pin_green_.close
    pin_red_.close

  functions -> List:
    return [
      Function
          --syntax="green_led(<true|false>)"
          --description="Turns the green LED on or off."
          --action=:: | args/List |
            pin_green_.set (args[0] ? 1 : 0),
      Function
          --syntax="red_led(<true|false>)"
          --description="Turns the red LED on or off."
          --action=:: | args/List |
            pin_red_.set (args[0] ? 1 : 0),
    ]
```

It's trivial to add more functions to the application. As long as there
  is a `Function` object that describes the function, OpenAI can use it.

[![Watch the video](https://img.youtube.com/vi/DNfOBLt1f9s/maxresdefault.jpg)](https://youtu.be/DNfOBLt1f9s)

## Setup
Make sure you have [Toit](toitlang.org) installed. The easiest is to use
  [Jaguar](https://github.com/toitlang/jaguar).

Install the dependencies (in this directory; or add `--project_root=<DIR>`).
- with Jaguar: `jag pkg install`
- with pure Toit: `toit.pkg install`

If you are using Jaguar (preferred), flash it to your device:
- `jag flash`


Create a new Telegram bot by running `/newbot`. '@BotFather' will as you
for a name and username, then provide the authentication token.

If you want your bot to be able to chat in groups, you need to disable
"Groups Privacy": go into the settings, by running `/mybots` and select
the bot you just created. Go to the "Group Privacy" section and disable
it.

Create an account at https://platform.openai.com/, and create an API key
in the [api-keys page](https://platform.openai.com/account/api-keys).

Take the provided `esp32-example.toit` and copy/rename it to
`esp32.toit` (or `esp32_<suffix>.toit` if you want to
run multiple bots).

Change the credentials in that file, then do the usual Jaguar installation
steps:
* optionally start the serial monitor: `jag monitor`
* run the bot: `jag run esp32.toit`

If you want to install the bot so it runs on boot:
* install the bot: `jag container install bot esp32.toit`

If you have questions, please ask on the [Toit Discord](https://discord.gg/Q7Y9VQ5nh2).

## Support
If you have questions, please ask on the [Toit Discord](https://discord.gg/Q7Y9VQ5nh2).
