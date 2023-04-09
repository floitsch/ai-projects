// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .telegram as real_main

TELEGRAM_TOKEN ::= "INSERT YOUR TOKEN HERE"
OPENAI_KEY ::= "INSERT YOUR KEY HERE"
CHAT_PASSWORD ::= "hunter2"

main:
  real_main.main
      --telegram_token=TELEGRAM_TOKEN
      --openai_key=OPENAI_KEY
      --chat_password=CHAT_PASSWORD
