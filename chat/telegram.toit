// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import host.os // For os.env.get.
import system.storage

import .chat-bot

/**
If there is a gap of more than MAX_GAP between messages, we clear the
conversation.
*/
MAX-GAP ::= Duration --m=3
/** The maximum number of messages we keep in memory for each chat. */
MAX-MESSAGES ::= 20

/** The bucket where we store the list of authenticated chat-ids. */
BUCKET-ID ::= "flash:github.com/floitsch/ai_projects/ai_chat"
/** The key where we store the list of authenticated chat-ids. */
AUTHENTICATED-KEY ::= "authenticated"

/**
Main entry point when running on the Desktop.

Takes the credentials from environment variables.
*/
main args:
  telegram-token := os.env.get "TELEGRAM_TOKEN"
  if not telegram-token or telegram-token == "":
    print "Please set the TELEGRAM_TOKEN environment variable."
    return

  openai-key := os.env.get "OPENAI_KEY"
  if not openai-key or openai-key == "":
    print "Please set the OPENAI_KEY environment variable."
    return

  openai-model := args.is-empty ? null : args[0]

  chat-password := os.env.get "CHAT_PASSWORD"
  if not chat-password or chat-password == "":
    print "Please set the CHAT_PASSWORD environment variable."
    return

  main
      --telegram-token=telegram-token
      --openai-key=openai-key
      --openai-model=openai-model
      --chat-password=chat-password

/**
Main entry point after the credentials have been set.

When running on an ESP32 there is typically a second file that contains
  the credentials and calls this function.
*/
main
    --telegram-token/string
    --openai-key/string
    --openai-model/string?=null
    --chat-password/string:
  bot := TelegramChatBot
      --telegram-token=telegram-token
      --openai-key=openai-key
      --openai-model=openai-model
      --chat-password=chat-password

  bot.run

class TelegramChatBot extends ChatBot:
  telegram-client_/telegram.Client? := ?

  bucket_/storage.Bucket

  password_/string
  // List of authenticated chat-ids.
  authenticated_/List

  my-name_/string
  my-username_/string

  constructor
      --telegram-token/string
      --openai-key/string
      --openai-model/string?=null
      --chat-password/string:
    telegram-client_ = telegram.Client --token=telegram-token
    password_ = chat-password

    bucket_ = storage.Bucket.open BUCKET-ID
    auth := bucket_.get AUTHENTICATED-KEY
    if not auth:
      auth = []
    else:
      // Make a copy so we can modify it later.
      auth = auth.map: it

    authenticated_ = auth

    my-user/telegram.User? := telegram-client_.get-me
    my-username_ = my-user.username
    my-name_ = my-user.first-name
    if my-user.last-name:
      my-name_ += " " + my-user.last-name

    super --openai-key=openai-key --openai-model=openai-model

  close:
    super
    if telegram-client_:
      telegram-client_.close
      telegram-client_ = null

  run:
    telegram-client_.listen --ignore-old: | update/telegram.Update? |
      // Eagerly clear old messages to relieve memory pressure.
      clear-old-messages_

      if update is not telegram.UpdateMessage:
        print "Ignoring update: $update"
        continue.listen

      too-old := Time.now - (MAX-GAP * 2)
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.date < too-old:
        print "Message too old: $message"
        continue.listen

      chat-id := message.chat.id
      is-direct-chat := message.chat and message.chat.type == telegram.Chat.TYPE-PRIVATE
      is-for-me := is-direct-chat or mentions_ message my-username_

      if is-for-me and message.text.starts-with "/authenticate":
        authenticate_ message.text chat-id
        continue.listen

      if not is-authenticated_ chat-id:
        if is-for-me:
          send-message_ --chat-id=chat-id
              "This chat is not authenticated. Run /authenticate <pw> $chat-id."
        continue.listen

      text := ?
      if is-direct-chat:
        text = message.text
      else:
        user := extract-author_ message
        prefix := user == "" ? "" : "$user: "
        if user == "":
          text = message.text
        else:
          text = "$user: $message.text"
      print "Got message: $text"

      timestamp := message.date
      // Allow the update and the message to be garbage collected.
      update = null
      message = null
      handle-message_ text --chat-id=chat-id --timestamp=timestamp --is-for-me=is-for-me

  /**
  Returns whether the $message has a mention for $username.
  */
  mentions_ message/telegram.Message username/string -> bool:
    if not message.entities: return false
    message.entities.do: | entity/telegram.MessageEntity |
      if entity.type == telegram.MessageEntity.TYPE-MENTION and
          // We can't use entity.offset and entity.length because
          // Toit uses UTF-8 and Telegram uses UTF-16.
          // TODO(florian): convert the offset and length to UTF-8.
          message.text.contains "@$username":
        return true
    return false

  /** Writes the updated $authenticated_ list to the storage bucket. */
  write-updated-authenticated_:
    bucket_[AUTHENTICATED-KEY] = authenticated_

  /** Extracts the author from the given $message. */
  extract-author_ message/telegram.Message -> string:
    result := ""
    if message.from:
      result = message.from.first-name
    if message.from.last-name:
      result += " " + message.from.last-name
    return result

  /**
  Whether the given $chat-id is authenticated.
  We don't do OpenAI requests for unauthenticated chats.
  */
  is-authenticated_ chat-id/int -> bool:
    // We could also do a map-lookup in 'all_messages_', since
    // only authenticated chat-ids are in there. But this is more
    // explicit.
    return authenticated_.contains chat-id

  /**
  Handles an authentication request.

  The given $chat-id is only used if the request does not contain a chat-id.
  */
  authenticate_ text/string chat-id/int:
    words := text.split " "
    if words.size < 2:
      send-message_ --chat-id=chat-id "Please provide the password."
      return

    if words.last == password_:
      all-messages_[chat-id] = Deque
      authenticated_.add chat-id
      write-updated-authenticated_
      send-message_ --chat-id=chat-id "Authenticated."
      return

    if words[words.size - 2] == password_:
      authenticated-chat-id := int.parse words.last --on-error=:
        send-message_ --chat-id=chat-id "Invalid chat-id."
        return

      all-messages_[authenticated-chat-id] = Deque
      authenticated_.add authenticated-chat-id
      write-updated-authenticated_
      send-message_ --chat-id=chat-id "Authenticated $authenticated-chat-id."
      return

    send-message_ --chat-id=chat-id "Invalid password."

  /** Sends a message to the telegram chat. */
  send-message_ text/string --chat-id/int:
    telegram-client_.send-message --chat-id=chat-id text
