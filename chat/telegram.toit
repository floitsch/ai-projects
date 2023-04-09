// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import telegram
import host.os // For os.env.get.
import monitor
import openai
import system.storage

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
main:
  telegram_token := os.env.get "TELEGRAM_TOKEN"
  if not telegram_token or telegram_token == "":
    print "Please set the TELEGRAM_TOKEN environment variable."
    return

  openai_key := os.env.get "OPENAI_KEY"
  if not openai_key or openai_key == "":
    print "Please set the OPENAI_KEY environment variable."
    return

  chat_password := os.env.get "CHAT_PASSWORD"
  if not chat_password or chat_password == "":
    print "Please set the CHAT_PASSWORD environment variable."
    return

  main
      --telegram_token=telegram_token
      --openai_key=openai_key
      --chat_password=chat_password

/**
Main entry point after the credentials have been set.

When running on an ESP32 there is typically a second file that contains
  the credentials and calls this function.
*/
main --telegram_token/string --openai_key/string --chat_password/string:
  bot := ChatBot
      --telegram_token=telegram_token
      --openai_key=openai_key
      --chat_password=chat_password

  bot.run

class TimestampedMessage:
  text/string
  timestamp/Time
  is_from_assistant/bool

  constructor --.text --.timestamp --.is_from_assistant:

class ChatBot:
  openai_client_/openai.Client? := ?
  telegram_client_/telegram.Client? := ?

  bucket_/storage.Bucket

  password_/string
  // List of authenticated chat-ids.
  authenticated_/List

  my_name_/string
  my_username_/string

  // Set of chat-ids that were already asked to authenticate.
  reported_authentication_requests_/Set := {}

  // Maps from chat-id to deque.
  // Only authenticated chat-ids are in this map.
  all_messages_/Map := {:}

  constructor
      --telegram_token/string
      --openai_key/string
      --chat_password/string:
    openai_client_ = openai.Client --key=openai_key
    telegram_client_ = telegram.Client --token=telegram_token
    password_ = chat_password

    bucket_ = storage.Bucket.open BUCKET_ID
    authenticated_ = bucket_.get AUTHENTICATED_KEY --if_absent=: []

    my_user/telegram.User? := telegram_client_.get_me
    my_username_ = my_user.username
    my_name_ = my_user.first_name
    if my_user.last_name:
      my_name_ += " " + my_user.last_name

  run:
    telegram_client_.listen: | update/telegram.Update? |
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
      is_for_me := (message.chat and message.chat.type == telegram.Chat.TYPE_PRIVATE) or
          mentions_ message my_username_

      if is_for_me and message.text.starts_with "/authenticate":
        authenticate_ message.text chat_id
        continue.listen

      if not is_authenticated_ chat_id:
        send_authentication_error_ chat_id
        continue.listen

      store_message_ message --chat_id=chat_id

      if is_for_me:
        // Allow the update and the message to be garbage collected.
        update = null
        message = null

        conversation := build_conversation_ chat_id
        response := openai_client_.complete_chat
            --conversation=conversation
            --max_tokens=300
        store_assistant_response_ response --chat_id=chat_id
        send_message_ response --chat_id=chat_id

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

  /** Returns the messages for the given $chat_id. */
  messages_for_ chat_id/int -> Deque:
    return all_messages_.get chat_id --init=: Deque

  /** Writes the updated $authenticated_ list to the storage bucket. */
  write_updated_authenticated_:
    bucket_[AUTHENTICATED_KEY] = authenticated_

  /**
  Drops old messages from all watched chats.
  Uses the $MAX_GAP constant to determine if a chat has moved on to
    a new topic (which leads to a new conversation for the AI bot).
  */
  clear_old_messages_:
    now := Time.now
    all_messages_.do: | chat_id/int messages/Deque |
      if messages.is_empty: continue.do
      last_message := messages.last
      if (last_message.timestamp.to now) > MAX_GAP:
        print "Clearing $chat_id"
        messages.clear

  /**
  Builds an OpenAI conversation for the given $chat_id.

  Returns a list of $openai.ChatMessage objects.
  */
  build_conversation_ chat_id/int -> List:
    result := [
      openai.ChatMessage.system "You are contributing to chat of potentially multiple people. Your name is '$my_name_'. Be short.",
    ]
    messages := messages_for_ chat_id
    messages.do: | timestamped_message/TimestampedMessage |
      if timestamped_message.is_from_assistant:
        result.add (openai.ChatMessage.assistant timestamped_message.text)
      else:
        // We are not combining multiple messages from the user.
        // Typically, the chat is a back and forth between the user and
        // the assistant. For memory reasons we prefer to make individual
        // messages.
        result.add (openai.ChatMessage.user timestamped_message.text)
    return result

  /** Extracts the author from the given $message. */
  extract_author_ message/telegram.Message -> string:
    result := ""
    if message.from:
      result = message.from.first_name
    if message.from.last_name:
      result += " " + message.from.last_name
    return result

  /** Stores the $response that the assistant produced in the chat. */
  store_assistant_response_ response/string --chat_id/int:
    messages := messages_for_ chat_id
    messages.add (TimestampedMessage
      --text=response
      --timestamp=Time.now
      --is_from_assistant)

  /**
  Stores a user-provided $message in the list of messages for the
    given $chat_id.
  */
  store_message_ message/telegram.Message --chat_id/int -> none:
    messages := messages_for_ chat_id
    // Drop messages if we have too many of them.
    if messages.size >= MAX_MESSAGES:
        messages.remove_first

    user := extract_author_ message
    prefix := user == "" ? "" : "$user: "
    text := ?
    if user == "":
      text = message.text
    else:
      text = "$user: $message.text"
    print "Got message: $text"
    new_timestamped_message := TimestampedMessage
        // We store the user with the message.
        // This is mainly so we don't need to create a new string
        // when we create the conversation.
        --text=text
        --timestamp=message.date
        --is_from_assistant=false
    messages.add new_timestamped_message

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

  /**
  Sends an authentication error with a request to provide the password.

  If the chat already received an authentication error, we don't send
    another one.
  */
  send_authentication_error_ chat_id/int:
    if reported_authentication_requests_.contains chat_id:
      return
    send_message_ --chat_id=chat_id
        "This chat ($chat_id) is not authenticated. Please provide the password."
    reported_authentication_requests_.add chat_id

  /** Sends a message to the telegram chat. */
  send_message_ text/string --chat_id/int:
    telegram_client_.send_message --chat_id=chat_id text
