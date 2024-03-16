// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import device-bot show Function
import gpio
import hc-sr04
import pixel-strip

LED-RING-PIN ::= 26

class LedRing:
  pin_/gpio.Pin
  strip_/pixel-strip.PixelStrip

  constructor:
    pin_ = gpio.Pin LED-RING-PIN
    strip_ = pixel-strip.PixelStrip.uart --pin=pin_ 12

  functions -> List:
    return [
      Function
          --syntax="set_gauge(<value>)"
          --description="Sets the gauge to the given value, which must be between 0 and 1."
          --action=:: | args/List |
            value := args[0]
            set-gauge value,
    ]

  set-gauge value/num:
    cut-off := 12 * value
    pixel-values := ByteArray 12: it < cut-off ? 0x10 : 00
    strip_.output pixel-values pixel-values pixel-values

  close:
    pin_.close

TRIGGER-PIN ::= 33
ECHO-PIN ::= 32
MIN-RATE-LIMIT-MS ::= 200

class DistanceSensor:
  trigger_/gpio.Pin
  echo_/gpio.Pin
  sensor_/hc-sr04.Driver
  last-run_/int := -1
  last-distance_/int := 0

  constructor:
    trigger_ = gpio.Pin TRIGGER-PIN
    echo_ = gpio.Pin ECHO-PIN
    sensor_ = hc-sr04.Driver --trigger=trigger_ --echo=echo_

  close:
    sensor_.close
    trigger_.close
    echo_.close

  functions -> List:
    return [
      Function
          --syntax="read_distance()"
          --description="Reads the distance in millimeters."
          --action=:: read-distance,
    ]

  read-distance -> int:
    // Add some rate limiting.
    now := Time.monotonic-us
    if now - last-run_ < MIN-RATE-LIMIT-MS * 1_000:
      sleep --ms=(MIN-RATE-LIMIT-MS - (now - last-run_) / 1000)
    distance := sensor_.read-distance
    last-run_ = Time.monotonic-us
    print "Distance: $distance"
    if not distance: return last-distance_
    last-distance_ = distance
    return distance
