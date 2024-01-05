/*

MixLit Firmware V2

For Arduino

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

*/

#include <Wire.h>
#include <FastLED.h>
#include <MIDIUSB.h>

#define NUM_OF_LED_STRIPS 5
#define NUM_OF_LEDS_PER_STRIP 8

const int NumOfSliders = 5;
char SliderIDs[NumOfSliders] = {'A', 'A', 'A', 'A', 'A'};
const int Sliders[NumOfSliders] = {A1, A2, A3, A4, A5};
int prevSliderState[NumOfSliders];
int SliderState[NumOfSliders];

int red = 0;
int green = 0;
int blue = 0;

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

void setLEDs(int iCurrentValue, uint8_t red, uint8_t green, uint8_t blue, int ledStrip)
{
  int iNumOfLedsOn = iCurrentValue / 128;
  int iFinalLedBrightness = (iCurrentValue % 128) * 2;

  for (int i = 0; i < 8; i++)
  {
    if (i == (7 - iNumOfLedsOn))
    {
      leds[ledStrip][i] = CRGB(iFinalLedBrightness, iFinalLedBrightness, iFinalLedBrightness);
    }
    else if (i > (7 - iNumOfLedsOn))
    {
      leds[ledStrip][i] = CRGB(red, green, blue);
    }
    else
    {
      leds[ledStrip][i] = CRGB(0, 0, 0);
    }
  }

  FastLED.show();
}

void setup()
{

  while (!Serial) {
    delay(10);
  }

  FastLED.addLeds<NEOPIXEL, 3>(leds[0], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<NEOPIXEL, 4>(leds[1], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<NEOPIXEL, 5>(leds[2], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<NEOPIXEL, 6>(leds[3], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<NEOPIXEL, 7>(leds[4], NUM_OF_LEDS_PER_STRIP);
}

void loop()
{
  String builtString = String("");

  for (int i = 0; i < NumOfSliders; i++)
  {
    FastLED.setBrightness(64);

    SliderState[i] = analogRead(Sliders[i]);

    int reversedValue = 1023 - SliderState[i];

    int diff = abs(SliderState[i] - prevSliderState[i]);

    if (diff > 2)
    {
      prevSliderState[i] = SliderState[i];

      builtString += String(SliderIDs[i]) + String(i + 1) + "|" + String(reversedValue);

      setLEDs(reversedValue, 255, 255, 255, i);

      if (i != NumOfSliders - 1)
      {
        builtString += String("|");
      }
    }
  }

  if (builtString.length() > 0)
  {
    Serial.println(builtString);
  }

  delay(10);
}