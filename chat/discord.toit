// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import discord
import host.os // For os.env.get.
import monitor
import .chat-bot

main:
  discord-token := os.env.get "DISCORD_TOKEN"
  if not discord-token or discord-token == "":
    print "Please set the DISCORD_TOKEN environment variable."
    return

  discord-url := os.env.get "DISCORD_URL"

  openai-key := os.env.get "OPENAI_KEY"
  if not openai-key or openai-key == "":
    print "Please set the OPENAI_KEY environment variable."
    return

  main
      --discord-token=discord-token
      --discord-url=discord-url
      --openai-key=openai-key


class DiscordChatBot extends ChatBot:
  discord-client_/discord.Client? := ?
  discord-mutex_/monitor.Mutex

  my-id_/string? := null
  my-name_/string? := null

  // Remember private channels, so we don't need to look them up all the time.
  private-channels_ := {}
  public-channels_ := {}

  constructor --discord-token/string --openai-key/string:
    discord-client_ = discord.Client --token=discord-token
    discord-mutex_ = monitor.Mutex

    super --openai-key=openai-key

  close:
    super
    if discord-client_:
      discord-client_.close
      discord-client_ = null

  get-my-roles_ -> Map:
    me := discord-client_.me
    // We could get this information also from the ready event, but we need to
    // get our ID here anyway.
    my-id_ = me.id
    my-name_ = me.username
    print "I am $my-name_ ($my-id_)"
    guilds := discord-client_.guilds
    result := {:}
    guilds.do: | guild/discord.Guild |
      id := guild.id
      my-member := discord-client_.guild-member --guild-id=id --user-id=my-id_
      result[id] = my-member.roles
    return result

  run:
    // Map from channel id to list of roles.
    roles := get-my-roles_

    intents := 0
      | discord.INTENT-GUILD-MEMBERS
      | discord.INTENT-GUILD-MESSAGES
      | discord.INTENT-DIRECT-MESSAGES
      | discord.INTENT-GUILD-MESSAGE-CONTENT

    accepted-forum-types := {
      discord.Channel.TYPE-GUILD-TEXT,
      discord.Channel.TYPE-GUILD-FORUM,
      discord.Channel.TYPE-PUBLIC-THREAD
    }

    discord-client_.listen --intents=intents: | event/discord.Event? |
      clear-old-messages_

      if event is discord.EventReady:
        print "Now listening for messages"
        continue.listen

      if event is not discord.EventMessageCreate:
        print "Ignoring event $event"
        continue.listen

      message/discord.Message? := (event as discord.EventMessageCreate).message
      channel-id := message.channel-id
      guild-id := message.guild-id
      if message.author.id == my-id_: continue.listen

      if not public-channels_.contains channel-id and
          not private-channels_.contains channel-id:
        channel := discord-client_.channel channel-id
        if not accepted-forum-types.contains channel.type:
          private-channels_.add channel-id
        else:
          public-channels_.add channel-id

      is-for-me := (message.mentions.any: it.id == my-id_) or
          (message.mention-roles.any: (roles.get guild-id --if-absent=:[]).contains it)

      if private-channels_.contains channel-id:
        if is-for-me: send-message_ "Sorry, I am shy in private 🙊" --chat-id=channel-id
        continue.listen

      content := message.content
      author := message.author.username
      event = null
      message = null

      text := "$author: $content"
      print "Message: $text"

      handle-message_ text --chat-id=channel-id --is-for-me=is-for-me

  send-message_ text/string --chat-id/string:
    discord-mutex_.do:
      discord-client_.send-message text --channel-id=chat-id

main --discord-token/string --discord-url/string? --openai-key/string:
  if discord-url and discord-url != "":
    print "To invite and authorize the bot to a channel go to $discord-url"

  bot := DiscordChatBot
      --discord-token=discord-token
      --openai-key=openai-key

  while true:
    catch --trace:
      bot.run
    sleep --ms=5_000
