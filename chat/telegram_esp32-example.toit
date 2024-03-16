// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .telegram as real-main

TELEGRAM-TOKEN ::= "INSERT YOUR TOKEN HERE"
OPENAI-KEY ::= "INSERT YOUR KEY HERE"
CHAT-PASSWORD ::= "hunter2"

main:
  real-main.main
      --telegram-token=TELEGRAM-TOKEN
      --openai-key=OPENAI-KEY
      --chat-password=CHAT-PASSWORD
