// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .discord as real-main

DISCORD-TOKEN ::= "INSERT YOUR TOKEN HERE"
DISCORD-URL ::= "INSERT YOUR AUTHENTICATION URL HERE"
OPENAI-KEY ::= "INSERT YOUR KEY HERE"

main:
  real-main.main
      --discord-token=DISCORD-TOKEN
      --discord-url=DISCORD-URL
      --openai-key=OPENAI-KEY
