// Copyright (C) 2023 Florian Loitsch.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .discord as real_main

DISCORD_TOKEN ::= "INSERT YOUR TOKEN HERE"
DISCORD_URL ::= "INSERT YOUR AUTHENTICATION URL HERE"
OPENAI_KEY ::= "INSERT YOUR KEY HERE"

main:
  real_main.main
      --discord_token=DISCORD_TOKEN
      --discord_url=DISCORD_URL
      --openai_key=OPENAI_KEY
