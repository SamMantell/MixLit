/*

MixLit Firmware V2

For Arduino Leonardo

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit, it is responsible for taking slider OUTPUTs, sending them to a PC over serial.

It also is responsible for control over the LEDS, these can be adjusted over serial by sending a string to the MixLit over serial as follows.



      0     0      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF       FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      |     |                               |                                                         |
 Slider ID  |   First set of HEX RGB values for the 8 leds on the strip     Second set of 8 values for if it is animated
            |
  Wether it is animated



RGB values are sent as 24 bits over 6 HEX values, the brightness of the LED can be controled by the RGB value, master brightness and the brightness used in the function to control the brightness of the final LED lit.

*/

#include <FastLED.h>

#define NUM_OF_LED_STRIPS 5
#define NUM_OF_SLIDERS 5
#define NUM_OF_POTENTIOMETERS 3
#define NUM_OF_LEDS_PER_STRIP 8

String serialDataFromPC;

const int Sliders[NUM_OF_SLIDERS] = {A0, A1, A2, A3, A4};
const int Potentiometers[NUM_OF_POTENTIOMETERS] = {A5, A6, A7};

const int LedStrips[NUM_OF_LED_STRIPS] = {11, 12, 13, 14, 15};

int previousState[NUM_OF_SLIDERS + NUM_OF_POTENTIOMETERS];
int currentState[NUM_OF_SLIDERS + NUM_OF_POTENTIOMETERS];

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

bool isAnimated = false;
char tempFullHexStorage[128];
char tempPartHexStorage[128];
uint32_t HEX_VALUE[8];

String test = "";

void setup()
{
  Serial.begin(115200);

  for (int i = 0; i > NUM_OF_SLIDERS; i++)
  {
    pinMode(Sliders[i], INPUT);
  }

  for (int i = 0; i > NUM_OF_POTENTIOMETERS; i++)
  {
    pinMode(Potentiometers[i], INPUT);
  }
}

void loop()
{
  test = "";

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    //Serial.println("Reading Slider: " + String(i));
    currentState[i] = analogRead(Sliders[i]);
  }
  for (int i = NUM_OF_SLIDERS + 1; i < NUM_OF_POTENTIOMETERS + NUM_OF_SLIDERS; i++)
  {
    //Serial.println("Reading Potentiometer: " + String(i));
    currentState[i] = analogRead(Sliders[i]);
  }

  for (int i = 0; i < NUM_OF_SLIDERS/* NUM_OF_POTENTIOMETERS*/; i++)
  {
    //Serial.println("Analysing Value: " + String(i));
    currentState[i] = 1023 - analogRead(Sliders[i]);

    if (abs(currentState[i] - previousState[i]) > 2)
    {
      if (currentState[i] > 1020)
      {
        currentState[i] = 1023;
      }
      else if (currentState[i] < 3)
      {
        currentState[i] = 0;
      }
      previousState[i] = currentState[i];
      test += i;
      test += "|";
      test += previousState[i];
      test += "|";
    }
    /*
    if ((currentState[i] - previousState[i] > 1))
    {
      if (currentState[i] == 1022)
      {
        currentState[i] = 1023;
      }
      else if (currentState[i] == 1)
      {
        currentState[i] = 0;
      }
      previousState[i] = currentState[i];
      builtString += String(i) + "|" + String(currentState[i]) + "|";
    }
    */
  }
  if (test != "")
  {
    Serial.println(test);
  }

  delay(20);
}