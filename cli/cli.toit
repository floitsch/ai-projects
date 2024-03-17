// Copyright (C) 2024 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import fs
import openai
import system
import host.pipe
import reader show BufferedReader

/**
Main entry point when running on the Desktop.

Takes the credentials from environment variables.
*/
main args/List --openai-key/string:
  model := (fs.basename system.program-name) == "ai4"
      ? "gpt-4-turbo-preview"
      : "gpt-3.5-turbo"

  input/string := ?
  if args.is-empty or args.last == "-":
    // Take the input from stdin.
    reader := BufferedReader pipe.stdin
    reader.buffer-all
    input = reader.read-string reader.buffered
    if args.size > 1:
      input = """
        $(args[..args.size - 1].join " ")
        $input"""
  else:
    input = args.join " "

  client := openai.Client
      --key=openai-key
      --chat-max-tokens=4096
      --chat-model=model

  conversation := [
    openai.ChatMessage.system "You are a helpful assistant. You do what is asked but aren't verbose about it.",
    openai.ChatMessage.user input,
  ]
  print (client.complete-chat --conversation=conversation)
