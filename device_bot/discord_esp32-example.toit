// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .main as real-main

OPENAI-KEY ::= "PUT YOUR OPENAI KEY HERE"

DISCORD-TOKEN ::= "PUT YOUR DISCORD TOKEN HERE"
DISCORD-URL ::= "PUT YOUR DISCORD AUTHORIZATION URL HERE"

main:
  real-main.main
      --openai-key=OPENAI-KEY
      --discord-token=DISCORD-TOKEN
      --discord-url=DISCORD-URL
