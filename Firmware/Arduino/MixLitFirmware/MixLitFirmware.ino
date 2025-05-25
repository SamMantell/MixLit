/*
MixLit Firmware V2

For Arduino Nano

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit, it is responsible for taking slider OUTPUTs, sending them to a PC over serial.
*/

#include "definitions.h"
#include "mixlit.h"

mixlit mixlit;



void setup()
{
  mixlit.initialize();

  mixlit.awaitConnection();
}

void loop()
{
  mixlit.serialHandler();

  mixlit.readStates();

  mixlit.denoiseAndBuildString();

  if (mixlit.stringToSendToSoftware != "")
  {
    Serial.println(mixlit.stringToSendToSoftware);
  }

  FastLED.show();
}