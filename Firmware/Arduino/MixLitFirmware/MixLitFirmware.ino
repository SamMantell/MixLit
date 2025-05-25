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

uint8_t loadingValue = 0;
bool loadingUp = true;

String stringToSendToSoftware = "";



void setup()
{
  Serial.begin(38400);

  for (int i = 0; i > NUM_OF_SLIDERS; i++)          pinMode(mixlit.sliders[i], INPUT);
  for (int i = 0; i > NUM_OF_POTENTIOMETERS; i++)   pinMode(mixlit.potentiometers[i], INPUT);
  for (int i = 0; i > NUM_OF_BUTTONS; i++)          pinMode(mixlit.buttons[i], INPUT);

  FastLED.addLeds<WS2812, 11, GRB>(mixlit.leds[0], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 10, GRB>(mixlit.leds[1], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 9, GRB>(mixlit.leds[2], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 8, GRB>(mixlit.leds[3], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 7, GRB>(mixlit.leds[4], NUM_OF_LEDS_PER_STRIP);

  while (true)
  {
    if (Serial.available())
    {
      char c = Serial.read();
        
      if (c == 63)
      {
          Serial.println("mixlit");
          FastLED.setBrightness(10);
          delay(200);
          return;
      }
    }

    delay(50);
    for (int i = 0; i < NUM_OF_SLIDERS; i++)
    {
      if (loadingUp)
      {
        loadingValue++;
        if (loadingValue == 254) loadingUp = false;
      }
      else
      {
        loadingValue--;
        if (loadingValue == 0) loadingUp = true;
      }
      // Serial.println(loadingValue/8);
      FastLED.setBrightness(loadingValue/8);
      // Serial.write("mixlit.setLEDs(128, ");
      // Serial.print(i);
      // Serial.println(");");
      mixlit.setLEDs(128, i);
    }
    FastLED.show();
  }
}

void loop()
{
  mixlit.serialHandler();

  stringToSendToSoftware = "";

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    mixlit.currentSliderState[i] = 1023 - analogRead(mixlit.sliders[i]);
  }
  for (int i = 0; i < NUM_OF_POTENTIOMETERS; i++)
  {
    mixlit.currentPotentiometerState[i] =  analogRead(mixlit.potentiometers[i]);
  }
  for (int i = 0; i < NUM_OF_BUTTONS; i++)
  {
    mixlit.currentButtonState[i] = digitalRead(mixlit.buttons[i]);
  }

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    if ((abs(mixlit.currentSliderState[i] - mixlit.previousSliderState[i]) > 5) || mixlit.needsUpdate)
    {
      if (mixlit.currentSliderState[i] > 1020)
      {
        mixlit.currentSliderState[i] = 1023;
      }
      else if (mixlit.currentSliderState[i] < 3)
      {
        mixlit.currentSliderState[i] = 0;
      }

      mixlit.setLEDs(mixlit.currentSliderState[i], i);
    }

    if ((abs(mixlit.currentSliderState[i] - mixlit.previousSliderState[i]) > 5))
    {
      mixlit.previousSliderState[i] = mixlit.currentSliderState[i];
      stringToSendToSoftware += i;
      stringToSendToSoftware += "|";
      stringToSendToSoftware += mixlit.previousSliderState[i];
      stringToSendToSoftware += "|";
    }
  }

  FastLED.show();
}