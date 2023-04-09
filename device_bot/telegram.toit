// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import monitor
import device_bot show *
import .peripherals

CHAT_ID ::= 483384462

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai_key/string --telegram_token/string:
  telegram_client := telegram.Client --token=telegram_token

  led_ring := LedRing
  distance_sensor := DistanceSensor

  functions := [
    Function
      --syntax="print(<message>)"
      --description="Print a message"
      --action=:: | args/List |
        message := args[0]
        telegram_client.send_message --chat_id=CHAT_ID "$message"
  ]
  functions.add_all led_ring.functions
  functions.add_all distance_sensor.functions
  device_bot := DeviceBot --openai_key=openai_key functions

  telegram_client.listen: | update/telegram.Update |
    if update is telegram.UpdateMessage:
      print "Got message: $update"
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.text == "/start":
        continue.listen

      chat_id := message.chat.id

      if chat_id != CHAT_ID:
        message = null
        telegram_client.send_message --chat_id=chat_id
            "Your chat-id $chat_id is not the allowed chat for this bot."
        continue.listen
      text := message.text
      message = null // Allow the full message to be garbage collected.

      device_bot.handle_message text --when_started=::
        telegram_client.send_message --chat_id=chat_id "Running"
