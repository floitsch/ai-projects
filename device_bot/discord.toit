// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import discord
import monitor
import device-bot show *
import .peripherals

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai-key/string --discord-token/string --discord-url/string:
  if discord-url != "":
    print "To invite and authorize the bot to a channel go to $discord-url"

  discord-client := discord.Client --token=discord-token
  discord-client.connect
  discord-mutex := monitor.Mutex

  channel-id := ""

  led-ring := LedRing
  distance-sensor := DistanceSensor

  device-bot/DeviceBot? := null

  // Don't start the but until we are connected to Discord.
  // The initial ready-message is quite heavy, so we prefer not to
  // have the DeviceBot running at the same time.
  start-rest := ::
    functions := [
      Function
        --syntax="print(<message>)"
        --description="Print a message"
        --action=:: | args/List |
          message := args[0]
          discord-mutex.do:
            discord-client.send-message --channel-id=channel-id "$message"
    ]
    functions.add-all led-ring.functions
    functions.add-all distance-sensor.functions
    device-bot = DeviceBot --openai-key=openai-key functions

  intents := 0
    | discord.INTENT-GUILD-MEMBERS
    | discord.INTENT-GUILD-MESSAGES
    | discord.INTENT-DIRECT-MESSAGES
    | discord.INTENT-GUILD-MESSAGE-CONTENT

  my-id/string? := null

  discord-client.listen --intents=intents: | event/discord.Event? |
    print "Got notification $event"
    if event is discord.EventReady:
      my-id = (event as discord.EventReady).user.id
      print "My id is $my-id"
      event = null  // Allow the event to be garbage collected.
      start-rest.call
      print "Now listening for messages"

    if event is discord.EventMessageCreate:
      message := (event as discord.EventMessageCreate).message
      if message.author.id == my-id: continue.listen

      print "Message: $message.content"

      channel-id = message.channel-id
      content := message.content
      device-bot.handle-message content --when-started=::
        discord-mutex.do:
          discord-client.send-message --channel-id=channel-id "Running"
