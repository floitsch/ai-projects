// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import host.os // For os.env.get.
import system.storage

import .chat_bot

/**
If there is a gap of more than MAX_GAP between messages, we clear the
conversation.
*/
MAX_GAP ::= Duration --m=3
/** The maximum number of messages we keep in memory for each chat. */
MAX_MESSAGES ::= 20

/** The bucket where we store the list of authenticated chat-ids. */
BUCKET_ID ::= "flash:github.com/floitsch/ai_projects/ai_chat"
/** The key where we store the list of authenticated chat-ids. */
AUTHENTICATED_KEY ::= "authenticated"

/**
Main entry point when running on the Desktop.

Takes the credentials from environment variables.
*/
main args:
  telegram_token := os.env.get "TELEGRAM_TOKEN"
  if not telegram_token or telegram_token == "":
    print "Please set the TELEGRAM_TOKEN environment variable."
    return

  openai_key := os.env.get "OPENAI_KEY"
  if not openai_key or openai_key == "":
    print "Please set the OPENAI_KEY environment variable."
    return

  openai_model := args.is_empty ? null : args[0]

  chat_password := os.env.get "CHAT_PASSWORD"
  if not chat_password or chat_password == "":
    print "Please set the CHAT_PASSWORD environment variable."
    return

  main
      --telegram_token=telegram_token
      --openai_key=openai_key
      --openai_model=openai_model
      --chat_password=chat_password

/**
Main entry point after the credentials have been set.

When running on an ESP32 there is typically a second file that contains
  the credentials and calls this function.
*/
main
    --telegram_token/string
    --openai_key/string
    --openai_model/string?=null
    --chat_password/string:
  bot := TelegramChatBot
      --telegram_token=telegram_token
      --openai_key=openai_key
      --openai_model=openai_model
      --chat_password=chat_password

  bot.run

class TelegramChatBot extends ChatBot:
  telegram_client_/telegram.Client? := ?

  bucket_/storage.Bucket

  password_/string
  // List of authenticated chat-ids.
  authenticated_/List

  my_name_/string
  my_username_/string

  constructor
      --telegram_token/string
      --openai_key/string
      --openai_model/string?=null
      --chat_password/string:
    telegram_client_ = telegram.Client --token=telegram_token
    password_ = chat_password

    bucket_ = storage.Bucket.open BUCKET_ID
    auth := bucket_.get AUTHENTICATED_KEY
    if not auth:
      auth = []
    else:
      // Make a copy so we can modify it later.
      auth = auth.map: it

    authenticated_ = auth

    my_user/telegram.User? := telegram_client_.get_me
    my_username_ = my_user.username
    my_name_ = my_user.first_name
    if my_user.last_name:
      my_name_ += " " + my_user.last_name

    super --openai_key=openai_key --openai_model=openai_model

  close:
    super
    if telegram_client_:
      telegram_client_.close
      telegram_client_ = null

  run:
    telegram_client_.listen --ignore_old: | update/telegram.Update? |
      // Eagerly clear old messages to relieve memory pressure.
      clear_old_messages_

      if update is not telegram.UpdateMessage:
        print "Ignoring update: $update"
        continue.listen

      too_old := Time.now - (MAX_GAP * 2)
      message/telegram.Message? := (update as telegram.UpdateMessage).message
      if message.date < too_old:
        print "Message too old: $message"
        continue.listen

      chat_id := message.chat.id
      is_direct_chat := message.chat and message.chat.type == telegram.Chat.TYPE_PRIVATE
      is_for_me := is_direct_chat or mentions_ message my_username_

      if is_for_me and message.text.starts_with "/authenticate":
        authenticate_ message.text chat_id
        continue.listen

      if not is_authenticated_ chat_id:
        if is_for_me:
          send_message_ --chat_id=chat_id
              "This chat is not authenticated. Run /authenticate <pw> $chat_id."
        continue.listen

      text := ?
      if is_direct_chat:
        text = message.text
      else:
        user := extract_author_ message
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
      handle-message_ text --chat-id=chat_id --timestamp=timestamp --is-for-me=is-for-me

  /**
  Returns whether the $message has a mention for $username.
  */
  mentions_ message/telegram.Message username/string -> bool:
    if not message.entities: return false
    message.entities.do: | entity/telegram.MessageEntity |
      if entity.type == telegram.MessageEntity.TYPE_MENTION and
          // We can't use entity.offset and entity.length because
          // Toit uses UTF-8 and Telegram uses UTF-16.
          // TODO(florian): convert the offset and length to UTF-8.
          message.text.contains "@$username":
        return true
    return false

  /** Writes the updated $authenticated_ list to the storage bucket. */
  write_updated_authenticated_:
    bucket_[AUTHENTICATED_KEY] = authenticated_

  /** Extracts the author from the given $message. */
  extract_author_ message/telegram.Message -> string:
    result := ""
    if message.from:
      result = message.from.first_name
    if message.from.last_name:
      result += " " + message.from.last_name
    return result

  /**
  Whether the given $chat_id is authenticated.
  We don't do OpenAI requests for unauthenticated chats.
  */
  is_authenticated_ chat_id/int -> bool:
    // We could also do a map-lookup in 'all_messages_', since
    // only authenticated chat-ids are in there. But this is more
    // explicit.
    return authenticated_.contains chat_id

  /**
  Handles an authentication request.

  The given $chat_id is only used if the request does not contain a chat-id.
  */
  authenticate_ text/string chat_id/int:
    words := text.split " "
    if words.size < 2:
      send_message_ --chat_id=chat_id "Please provide the password."
      return

    if words.last == password_:
      all_messages_[chat_id] = Deque
      authenticated_.add chat_id
      write_updated_authenticated_
      send_message_ --chat_id=chat_id "Authenticated."
      return

    if words[words.size - 2] == password_:
      authenticated_chat_id := int.parse words.last --on_error=:
        send_message_ --chat_id=chat_id "Invalid chat-id."
        return

      all_messages_[authenticated_chat_id] = Deque
      authenticated_.add authenticated_chat_id
      write_updated_authenticated_
      send_message_ --chat_id=chat_id "Authenticated $authenticated_chat_id."
      return

    send_message_ --chat_id=chat_id "Invalid password."

  /** Sends a message to the telegram chat. */
  send_message_ text/string --chat_id/int:
    telegram_client_.send_message --chat_id=chat_id text
