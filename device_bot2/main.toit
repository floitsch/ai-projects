// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import device-bot show *
import gpio
import dhtxx.dht11

LED-GREEN-PIN ::= 23
LED-RED-PIN ::= 22

class Leds:
  pin-green_/gpio.Pin
  pin-red_/gpio.Pin

  constructor:
    pin-green_ = gpio.Pin LED-GREEN-PIN --output
    pin-red_ = gpio.Pin LED-RED-PIN --output

  close:
    pin-green_.close
    pin-red_.close

  functions -> List:
    return [
      Function
          --syntax="green_led(<true|false>)"
          --description="Turns the green LED on or off."
          --action=:: | args/List |
            pin-green_.set (args[0] ? 1 : 0),
      Function
          --syntax="red_led(<true|false>)"
          --description="Turns the red LED on or off."
          --action=:: | args/List |
            pin-red_.set (args[0] ? 1 : 0),
    ]


DHT11-PIN ::= 32

class Dht11Sensor:
  data_/gpio.Pin
  sensor_/dht11.Dht11

  constructor:
    data_ = gpio.Pin DHT11-PIN
    sensor_ = dht11.Dht11 data_

  close:
    data_.close

  functions -> List:
    return [
      Function
          --syntax="temperature()"
          --description="Reads the temperature in C as a float"
          --action=:: sensor_.read-temperature,
      Function
          --syntax="humidity()"
          --description="Reads the humidity in % as a float"
          --action=:: sensor_.read-humidity,
    ]

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai-key/string --telegram-token/string:
  leds := Leds
  dht11-sensor := Dht11Sensor

  print dht11-sensor.sensor_.read-temperature

  // Connect to Telegram
  telegram-client := telegram.Client --token=telegram-token

  // Keep track of the last chat-id we've seen.
  // A more sophisticated bot would need to make sure that
  // only authenticated users can manipulate the device.
  chat-id/int? := null

  // Give the device a way to send messages to us.
  functions := [
    Function
      --syntax="print(<message>)"
      --description="Print a message"
      --action=:: | args/List |
        message := args[0]
        telegram-client.send-message --chat-id=chat-id "$message"
  ]
  functions.add-all leds.functions
  functions.add-all dht11-sensor.functions

  // Create a device bot.
  device-bot := DeviceBot --openai-key=openai-key functions

  // Start listening to new messages and interpret them.
  telegram-client.listen: | update/telegram.Update |
    if update is telegram.UpdateMessage:
      print "Got message: $update"
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.text == "/start":
        continue.listen

      chat-id = message.chat.id
      device-bot.handle-message message.text --when-started=::
        telegram-client.send-message --chat-id=chat-id "Running"
