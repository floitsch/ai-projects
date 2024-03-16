// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import openai
import ntp
import esp32 show adjust-real-time-clock

/**
If there is a gap of more than MAX_GAP between messages, we clear the
conversation.
*/
MAX-GAP ::= Duration --m=3
/** The maximum number of messages we keep in memory for each chat. */
MAX-MESSAGES ::= 20

class TimestampedMessage:
  text/string
  timestamp/Time
  is-from-assistant/bool

  constructor --.text --.timestamp --.is-from-assistant:

abstract class ChatBot:
  // The client is created lazily, to avoid memory pressure during startup.
  openai-client_/openai.Client? := null
  openai-key_/string? := ?
  openai-model_/string?

  last-ntp-sync_/Time? := null

  // Maps from chat-id to deque.
  // Only authenticated chat-ids are in this map.
  all-messages_/Map := {:}

  constructor --openai-key/string --openai-model/string?=null:
    openai-key_ = openai-key
    openai-model_ = openai-model

  close:
    if openai-client_:
      openai-client_.close
      openai-client_ = null
      openai-key_ = null

  /** The name of the bot. Sent as a system message. */
  abstract my-name_ -> string

  /** Sends a message to the given $chat-id. */
  abstract send-message_ text/string --chat-id/any

  /**
  Runs the bot.

  # Inheritance
  Run $clear-old-messages_ before handling a new event from the server.
  If the message is a text message, call $store-message_.
  If the message is for the bot, call $send-response_.
  */
  abstract run -> none

  /** Returns the messages for the given $chat-id. */
  messages-for_ chat-id/any -> Deque:
    return all-messages_.get chat-id --init=: Deque

  handle-message_ text/string --chat-id/any --timestamp/Time=Time.now --is-for-me/bool:
    if is-for-me and text == "RESET":
      all-messages_.remove chat-id
      return

    store-message_ text --chat-id=chat-id --timestamp=timestamp
    if is-for-me:
      send-response_ chat-id

  /**
  Drops old messages from all watched chats.
  Uses the $MAX-GAP constant to determine if a chat has moved on to
    a new topic (which leads to a new conversation for the AI bot).
  */
  clear-old-messages_:
    now := ?
    if not last-ntp-sync_ or (Duration.since last-ntp-sync_) > (Duration --h=12):
      ntp-result := ntp.synchronize
      if ntp-result:
        adjust-real-time-clock ntp-result.adjustment
      // If the NTP sync failed, we don't do anything.
      now = Time.now
      last-ntp-sync_ = now
    else:
      now = Time.now

    if now < (Time.utc --year=1971 --month=1 --day=1):
      // The clock is not set. We can't do anything.
      print "Clock is not set. Can't clear old messages."
      return
    all-messages_.do: | chat-id/any messages/Deque |
      print "Message size: $chat-id $messages.size"
      if messages.is-empty: continue.do
      last-message := messages.last
      if (last-message.timestamp.to now) > MAX-GAP:
        print "Clearing old messages for chat $chat-id."
        messages.clear

  /**
  Builds an OpenAI conversation for the given $chat-id.

  Returns a list of $openai.ChatMessage objects.
  */
  build-conversation_ chat-id/any -> List:
    result := [
      openai.ChatMessage.system "You are contributing to chat of potentially multiple people. Your name is '$my-name_'. Be short.",
    ]
    messages := messages-for_ chat-id
    messages.do: | timestamped-message/TimestampedMessage |
      if timestamped-message.is-from-assistant:
        result.add (openai.ChatMessage.assistant timestamped-message.text)
      else:
        // We are not combining multiple messages from the user.
        // Typically, the chat is a back and forth between the user and
        // the assistant. For memory reasons we prefer to make individual
        // messages.
        result.add (openai.ChatMessage.user timestamped-message.text)
    return result

  /** Stores the $response that the assistant produced in the chat. */
  store-assistant-response_ response/string --chat-id/any:
    messages := messages-for_ chat-id
    messages.add (TimestampedMessage
      --text=response
      --timestamp=Time.now
      --is-from-assistant)

  /**
  Stores a user-provided $text in the list of messages for the
    given $chat-id.
  The $text should contain the name of the author.
  */
  store-message_ text/string --chat-id/any --timestamp/Time=Time.now -> none:
    messages := messages-for_ chat-id
    // Drop messages if we have too many of them.
    if messages.size >= MAX-MESSAGES:
        messages.remove-first

    new-timestamped-message := TimestampedMessage
        // We store the user with the message.
        // This is mainly so we don't need to create a new string
        // when we create the conversation.
        --text=text
        --timestamp=timestamp
        --is-from-assistant=false
    messages.add new-timestamped-message

  /**
  Sends a response to the given $chat-id.
  */
  send-response_ chat-id/any:
    if not openai-client_:
      if not openai-key_: throw "Closed"
      openai-client_ = openai.Client --key=openai-key_ --chat-model=openai-model_

    conversation := build-conversation_ chat-id
    response := openai-client_.complete-chat
        --conversation=conversation
        --max-tokens=300
    store-assistant-response_ response --chat-id=chat-id
    send-message_ response --chat-id=chat-id
