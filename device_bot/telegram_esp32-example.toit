// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .telegram as real_main

OPENAI_KEY ::= "PUT YOUR OPENAI KEY HERE"
TELEGRAM_TOKEN ::= "PUT YOUR TELEGRAM TOKEN HERE"

main:
  real_main.main
      --openai_key=OPENAI_KEY
      --telegram_token=TELEGRAM_TOKEN
