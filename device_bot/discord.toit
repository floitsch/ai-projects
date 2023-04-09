// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import discord
import monitor
import device_bot show *
import .peripherals

/**
Main entry point.

Take the checked-in 'esp32-example.toit' and rename it to esp32.toit.
Then add your credentials, and install it on your ESP32.
*/
main --openai_key/string --discord_token/string --discord_url/string:
  if discord_url != "":
    print "To invite and authorize the bot to a channel go to $discord_url"

  discord_client := discord.Client --token=discord_token
  discord_client.connect
  discord_mutex := monitor.Mutex

  channel_id := ""

  led_ring := LedRing
  distance_sensor := DistanceSensor

  device_bot/DeviceBot? := null

  // Don't start the but until we are connected to Discord.
  // The initial ready-message is quite heavy, so we prefer not to
  // have the DeviceBot running at the same time.
  start_rest := ::
    functions := [
      Function
        --syntax="print(<message>)"
        --description="Print a message"
        --action=:: | args/List |
          message := args[0]
          discord_mutex.do:
            discord_client.send_message --channel_id=channel_id "$message"
    ]
    functions.add_all led_ring.functions
    functions.add_all distance_sensor.functions
    device_bot = DeviceBot --openai_key=openai_key functions

  intents := 0
    | discord.INTENT_GUILD_MEMBERS
    | discord.INTENT_GUILD_MESSAGES
    | discord.INTENT_DIRECT_MESSAGES
    | discord.INTENT_GUILD_MESSAGE_CONTENT

  my_id/string? := null

  discord_client.listen --intents=intents: | event/discord.Event? |
    print "Got notification $event"
    if event is discord.EventReady:
      my_id = (event as discord.EventReady).user.id
      print "My id is $my_id"
      event = null  // Allow the event to be garbage collected.
      start_rest.call
      print "Now listening for messages"

    if event is discord.EventMessageCreate:
      message := (event as discord.EventMessageCreate).message
      if message.author.id == my_id: continue.listen

      print "Message: $message.content"

      channel_id = message.channel_id
      content := message.content
      device_bot.handle_message content --when_started=::
        discord_mutex.do:
          discord_client.send_message --channel_id=channel_id "Running"
