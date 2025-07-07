/*
MixLit Firmware V2

For Arduino Nano

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit, it is responsible for taking slider OUTPUTs, sending them to a PC over serial.

Example of changing a slider colour pallete
This would change slider 1 to be a red to yellow gradient with no animation
10FFAA00FF9B00FF8C00FF7B00FF6900FF5400FF3A00FF0000

*/

#include "definitions.h"
#include "mixlit.hpp"

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