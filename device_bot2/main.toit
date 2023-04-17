// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import device_bot show *
import gpio
import dhtxx.dht11

LED_GREEN_PIN ::= 23
LED_RED_PIN ::= 22

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


DHT11_PIN ::= 32

class Dht11Sensor:
  data_/gpio.Pin
  sensor_/dht11.Dht11

  constructor:
    data_ = gpio.Pin DHT11_PIN
    sensor_ = dht11.Dht11 data_

  close:
    data_.close

  functions -> List:
    return [
      Function
          --syntax="temperature()"
          --description="Reads the temperature in C as a float"
          --action=:: sensor_.read_temperature,
      Function
          --syntax="humidity()"
          --description="Reads the humidity in % as a float"
          --action=:: sensor_.read_humidity,
    ]

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai_key/string --telegram_token/string:
  leds := Leds
  dht11_sensor := Dht11Sensor

  print dht11_sensor.sensor_.read_temperature

  // Connect to Telegram
  telegram_client := telegram.Client --token=telegram_token

  // Keep track of the last chat-id we've seen.
  // A more sophisticated bot would need to make sure that
  // only authenticated users can manipulate the device.
  chat_id/int? := null

  // Give the device a way to send messages to us.
  functions := [
    Function
      --syntax="print(<message>)"
      --description="Print a message"
      --action=:: | args/List |
        message := args[0]
        telegram_client.send_message --chat_id=chat_id "$message"
  ]
  functions.add_all leds.functions
  functions.add_all dht11_sensor.functions

  // Create a device bot.
  device_bot := DeviceBot --openai_key=openai_key functions

  // Start listening to new messages and interpret them.
  telegram_client.listen: | update/telegram.Update |
    if update is telegram.UpdateMessage:
      print "Got message: $update"
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.text == "/start":
        continue.listen

      chat_id = message.chat.id
      device_bot.handle_message message.text --when_started=::
        telegram_client.send_message --chat_id=chat_id "Running"
