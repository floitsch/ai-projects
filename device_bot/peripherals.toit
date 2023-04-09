// Copyright (C) 2023 Florian Loitsch. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import device_bot show Function
import gpio
import hc_sr04
import pixel_strip

LED_RING_PIN ::= 26

class LedRing:
  pin_/gpio.Pin
  strip_/pixel_strip.PixelStrip

  constructor:
    pin_ = gpio.Pin LED_RING_PIN
    strip_ = pixel_strip.PixelStrip.uart --pin=pin_ 12

  functions -> List:
    return [
      Function
          --syntax="set_gauge(<value>)"
          --description="Sets the gauge to the given value, which must be between 0 and 1."
          --action=:: | args/List |
            value := args[0]
            set_gauge value,
    ]

  set_gauge value/num:
    cut_off := 12 * value
    pixel_values := ByteArray 12: it < cut_off ? 0x10 : 00
    strip_.output pixel_values pixel_values pixel_values

  close:
    pin_.close

TRIGGER_PIN ::= 33
ECHO_PIN ::= 32
MIN_RATE_LIMIT_MS ::= 200

class DistanceSensor:
  trigger_/gpio.Pin
  echo_/gpio.Pin
  sensor_/hc_sr04.Driver
  last_run_/int := -1
  last_distance_/int := 0

  constructor:
    trigger_ = gpio.Pin TRIGGER_PIN
    echo_ = gpio.Pin ECHO_PIN
    sensor_ = hc_sr04.Driver --trigger=trigger_ --echo=echo_

  close:
    sensor_.close
    trigger_.close
    echo_.close

  functions -> List:
    return [
      Function
          --syntax="read_distance()"
          --description="Reads the distance in millimeters."
          --action=:: read_distance,
    ]

  read_distance -> int:
    // Add some rate limiting.
    now := Time.monotonic_us
    if now - last_run_ < MIN_RATE_LIMIT_MS * 1_000:
      sleep --ms=(MIN_RATE_LIMIT_MS - (now - last_run_) / 1000)
    distance := sensor_.read_distance
    last_run_ = Time.monotonic_us
    print "Distance: $distance"
    if not distance: return last_distance_
    last_distance_ = distance
    return distance
