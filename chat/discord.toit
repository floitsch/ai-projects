// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import discord
import host.os // For os.env.get.
import monitor
import .chat_bot

main:
  discord_token := os.env.get "DISCORD_TOKEN"
  if not discord_token or discord_token == "":
    print "Please set the DISCORD_TOKEN environment variable."
    return

  discord_url := os.env.get "DISCORD_URL"

  openai_key := os.env.get "OPENAI_KEY"
  if not openai_key or openai_key == "":
    print "Please set the OPENAI_KEY environment variable."
    return

  main
      --discord_token=discord_token
      --discord_url=discord_url
      --openai_key=openai_key


class DiscordChatBot extends ChatBot:
  discord_client_/discord.Client? := ?
  discord_mutex_/monitor.Mutex

  my_id_/string? := null
  my_name_/string? := null

  // Remember private channels, so we don't need to look them up all the time.
  private_channels_ := {}
  public_channels_ := {}

  constructor --discord_token/string --openai_key/string:
    discord_client_ = discord.Client --token=discord_token
    discord_mutex_ = monitor.Mutex

    super --openai_key=openai_key

  close:
    super
    if discord_client_:
      discord_client_.close
      discord_client_ = null

  get_my_roles_ -> Map:
    me := discord_client_.me
    // We could get this information also from the ready event, but we need to
    // get our ID here anyway.
    my_id_ = me.id
    my_name_ = me.username
    print "I am $my_name_ ($my_id_)"
    guilds := discord_client_.guilds
    result := {:}
    guilds.do: | guild/discord.Guild |
      id := guild.id
      my_member := discord_client_.guild_member --guild_id=id --user_id=my_id_
      result[id] = my_member.roles
    return result

  run:
    // Map from channel id to list of roles.
    roles := get_my_roles_

    intents := 0
      | discord.INTENT_GUILD_MEMBERS
      | discord.INTENT_GUILD_MESSAGES
      | discord.INTENT_DIRECT_MESSAGES
      | discord.INTENT_GUILD_MESSAGE_CONTENT

    accepted_forum_types := {
      discord.Channel.TYPE_GUILD_TEXT,
      discord.Channel.TYPE_GUILD_FORUM,
      discord.Channel.TYPE_PUBLIC_THREAD
    }

    discord_client_.listen --intents=intents: | event/discord.Event? |
      clear_old_messages_

      if event is discord.EventReady:
        print "Now listening for messages"
        continue.listen

      if event is not discord.EventMessageCreate:
        print "Ignoring event $event"
        continue.listen

      message/discord.Message? := (event as discord.EventMessageCreate).message
      channel_id := message.channel_id
      guild_id := message.guild_id
      if message.author.id == my_id_: continue.listen

      if not public_channels_.contains channel_id and
          not private_channels_.contains channel_id:
        channel := discord_client_.channel channel_id
        if not accepted_forum_types.contains channel.type:
          private_channels_.add channel_id
        else:
          public_channels_.add channel_id

      is_for_me := (message.mentions.any: it.id == my_id_) or
          (message.mention_roles.any: (roles.get guild_id --if_absent=:[]).contains it)

      if private_channels_.contains channel_id:
        if is_for_me: send_message_ "Sorry, I am shy in private 🙊" --chat_id=channel_id
        continue.listen

      content := message.content
      author := message.author.username
      event = null
      message = null

      text := "$author: $content"
      print "Message: $text"

      store_message_ text --chat_id=channel_id

      if is_for_me:
        send_response_ channel_id

  send_message_ text/string --chat_id/string:
    discord_mutex_.do:
      discord_client_.send_message text --channel_id=chat_id

main --discord_token/string --discord_url/string? --openai_key/string:
  if discord_url and discord_url != "":
    print "To invite and authorize the bot to a channel go to $discord_url"

  bot := DiscordChatBot
      --discord_token=discord_token
      --openai_key=openai_key

  bot.run
