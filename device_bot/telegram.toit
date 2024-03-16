// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import monitor
import device-bot show *
import .peripherals

CHAT-ID ::= 483384462

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai-key/string --telegram-token/string:
  telegram-client := telegram.Client --token=telegram-token

  led-ring := LedRing
  distance-sensor := DistanceSensor

  functions := [
    Function
      --syntax="print(<message>)"
      --description="Print a message"
      --action=:: | args/List |
        message := args[0]
        telegram-client.send-message --chat-id=CHAT-ID "$message"
  ]
  functions.add-all led-ring.functions
  functions.add-all distance-sensor.functions
  device-bot := DeviceBot --openai-key=openai-key functions

  telegram-client.listen: | update/telegram.Update |
    if update is telegram.UpdateMessage:
      print "Got message: $update"
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.text == "/start":
        continue.listen

      chat-id := message.chat.id

      if chat-id != CHAT-ID:
        message = null
        telegram-client.send-message --chat-id=chat-id
            "Your chat-id $chat-id is not the allowed chat for this bot."
        continue.listen
      text := message.text
      message = null // Allow the full message to be garbage collected.

      device-bot.handle-message text --when-started=::
        telegram-client.send-message --chat-id=chat-id "Running"
