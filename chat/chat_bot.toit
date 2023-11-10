// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import openai
import ntp
import esp32 show adjust_real_time_clock

/**
If there is a gap of more than MAX_GAP between messages, we clear the
conversation.
*/
MAX_GAP ::= Duration --m=3
/** The maximum number of messages we keep in memory for each chat. */
MAX_MESSAGES ::= 20

class TimestampedMessage:
  text/string
  timestamp/Time
  is_from_assistant/bool

  constructor --.text --.timestamp --.is_from_assistant:

abstract class ChatBot:
  // The client is created lazily, to avoid memory pressure during startup.
  openai_client_/openai.Client? := null
  openai_key_/string? := ?
  openai_model_/string?

  last_ntp_sync_/Time? := null

  // Maps from chat-id to deque.
  // Only authenticated chat-ids are in this map.
  all_messages_/Map := {:}

  constructor --openai_key/string --openai_model/string?=null:
    openai_key_ = openai_key
    openai_model_ = openai_model

  close:
    if openai_client_:
      openai_client_.close
      openai_client_ = null
      openai_key_ = null

  /** The name of the bot. Sent as a system message. */
  abstract my_name_ -> string

  /** Sends a message to the given $chat_id. */
  abstract send_message_ text/string --chat_id/any

  /**
  Runs the bot.

  # Inheritance
  Run $clear_old_messages_ before handling a new event from the server.
  If the message is a text message, call $store_message_.
  If the message is for the bot, call $send_response_.
  */
  abstract run -> none

  /** Returns the messages for the given $chat_id. */
  messages_for_ chat_id/any -> Deque:
    return all_messages_.get chat_id --init=: Deque

  /**
  Drops old messages from all watched chats.
  Uses the $MAX_GAP constant to determine if a chat has moved on to
    a new topic (which leads to a new conversation for the AI bot).
  */
  clear_old_messages_:
    now := ?
    if not last_ntp_sync_ or (Duration.since last_ntp_sync_) > (Duration --h=12):
      ntp_result := ntp.synchronize
      if ntp_result:
        adjust_real_time_clock ntp_result.adjustment
      // If the NTP sync failed, we don't do anything.
      now = Time.now
      last_ntp_sync_ = now
    else:
      now = Time.now

    if now < (Time.utc --year=1971 --month=1 --day=1):
      // The clock is not set. We can't do anything.
      print "Clock is not set. Can't clear old messages."
      return
    all_messages_.do: | chat_id/any messages/Deque |
      print "Message size: $chat_id $messages.size"
      if messages.is_empty: continue.do
      last_message := messages.last
      if (last_message.timestamp.to now) > MAX_GAP:
        print "Clearing old messages for chat $chat_id."
        messages.clear

  /**
  Builds an OpenAI conversation for the given $chat_id.

  Returns a list of $openai.ChatMessage objects.
  */
  build_conversation_ chat_id/any -> List:
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

  /** Stores the $response that the assistant produced in the chat. */
  store_assistant_response_ response/string --chat_id/any:
    messages := messages_for_ chat_id
    messages.add (TimestampedMessage
      --text=response
      --timestamp=Time.now
      --is_from_assistant)

  /**
  Stores a user-provided $text in the list of messages for the
    given $chat_id.
  The $text should contain the name of the author.
  */
  store_message_ text/string --chat_id/any --timestamp/Time=Time.now -> none:
    messages := messages_for_ chat_id
    // Drop messages if we have too many of them.
    if messages.size >= MAX_MESSAGES:
        messages.remove_first

    new_timestamped_message := TimestampedMessage
        // We store the user with the message.
        // This is mainly so we don't need to create a new string
        // when we create the conversation.
        --text=text
        --timestamp=timestamp
        --is_from_assistant=false
    messages.add new_timestamped_message

  /**
  Sends a response to the given $chat_id.
  */
  send_response_ chat_id/any:
    if not openai_client_:
      if not openai_key_: throw "Closed"
      openai_client_ = openai.Client --key=openai_key_ --chat_model=openai_model_

    conversation := build_conversation_ chat_id
    response := openai_client_.complete_chat
        --conversation=conversation
        --max_tokens=300
    store_assistant_response_ response --chat_id=chat_id
    send_message_ response --chat_id=chat_id
