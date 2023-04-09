// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .main as real_main

OPENAI_KEY ::= "PUT YOUR OPENAI KEY HERE"

DISCORD_TOKEN ::= "PUT YOUR DISCORD TOKEN HERE"
DISCORD_URL ::= "PUT YOUR DISCORD AUTHORIZATION URL HERE"

main:
  real_main.main
      --openai_key=OPENAI_KEY
      --discord_token=DISCORD_TOKEN
      --discord_url=DISCORD_URL
