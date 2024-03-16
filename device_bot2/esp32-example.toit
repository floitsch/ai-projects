// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import .telegram as real-main

OPENAI-KEY ::= "PUT YOUR OPENAI KEY HERE"
TELEGRAM-TOKEN ::= "PUT YOUR TELEGRAM TOKEN HERE"

main:
  real-main.main
      --openai-key=OPENAI-KEY
      --telegram-token=TELEGRAM-TOKEN
