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

// Definitions for MixLit specifications
#define NUM_OF_SLIDERS 5
#define NUM_OF_POTENTIOMETERS 3
#define NUM_OF_LED_STRIPS 5
#define NUM_OF_LEDS_PER_STRIP 8
#define NUM_OF_BUTTONS 5

// Pin Definitions
const int Sliders[NUM_OF_SLIDERS] = {A4, A3, A2, A1, A0};
const int Potentiometers[NUM_OF_POTENTIOMETERS] = {A5, A7, A6};
const int LedStrips[NUM_OF_LED_STRIPS] = {11, 10, 9, 8, 7};
const int Buttons[NUM_OF_BUTTONS] = {6, 5, 4, 3, 2};
const String ButtonNames[NUM_OF_BUTTONS] = {"A", "B", "C", "D", "E"};

// State Variables
int previousSliderState[NUM_OF_SLIDERS];
int currentSliderState[NUM_OF_SLIDERS];

int currentPotentiometerState[NUM_OF_POTENTIOMETERS];
int previousPotentiometerState[NUM_OF_POTENTIOMETERS];

bool previousButtonState[NUM_OF_BUTTONS];
bool currentButtonState[NUM_OF_BUTTONS];

// CRGB Definitions
CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];


// LED Strip Variables for Colour Control
bool isAnimated = false;
uint8_t ColorIndex;
int colorIndexOffset;

CRGBPalette16 All_ColorPallete[NUM_OF_LED_STRIPS] = 
{
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF,
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                  ),
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFF0000, 0xFF0000,  0xFF0000,
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                  ),
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0x00FF00, 0x00FF00,  0x00FF00,
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                  ),
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0x0000FF, 0x0000FF,  0x0000FF,
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                  ),
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFF00FF, 0xFF00FF,  0xFF00FF,
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                  )
};

// Variables for Serial Recieve
char tempFullHexStorage[128];
char tempPartHexStorage[128];
uint32_t HEX_VALUE[8];
int SliderToChange;
bool needsUpdate;

// Strings for Sending Data to Software
String stringToSendToSoftware;
String serialDataFromPC;

uint8_t loadingValue = 0;
bool loadingUp = true;

// SetLEDs Function for Led Strip Control
void setLEDs(int iCurrentValue, int ledStrip)
{
  if (isAnimated) colorIndexOffset++;

  else colorIndexOffset = 0;

  // this will take the 10 bit value from the slider, and use bitshift and remainder calculation to get the number of leds on and the brightness of the final one.
  uint8_t iNumOfLedsOn = iCurrentValue >> 7;
  uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

  for (int i = 0; i < 8; i++)
  {
    ColorIndex = 16*i + colorIndexOffset;

    if (i == (NUM_OF_LEDS_PER_STRIP - 1 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, iFinalLedBrightness);
  
    else if (i > (NUM_OF_LEDS_PER_STRIP - 1 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, 255);
      
    else                                                        leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, 0);
  }
}

// Function to read data from the pc and use it to set the LED Colours on the MixLit
void readSerialDataAndSetLEDs() {
  serialDataFromPC = Serial.readString();

  serialDataFromPC.toCharArray(tempFullHexStorage, 128);

  tempPartHexStorage[1] = 0;
  tempPartHexStorage[2] = 0;
  tempPartHexStorage[3] = 0;
  tempPartHexStorage[4] = 0;
  tempPartHexStorage[5] = 0;

  tempPartHexStorage[0] = tempFullHexStorage[0];
  HEX_VALUE[0] = strtol(tempPartHexStorage, NULL, 16);
  SliderToChange = HEX_VALUE[0];

  tempPartHexStorage[0] = tempFullHexStorage[1];
  HEX_VALUE[0] = strtol(tempPartHexStorage, NULL, 16);
  isAnimated = bool(HEX_VALUE[0]);

  for (int i = 0; i < 16; i++)
  {
    for (int j = 0; j < 6; j++)
    {
      tempPartHexStorage[j] = tempFullHexStorage[2+(6*i+j)];
    }
    HEX_VALUE[i] = strtol(tempPartHexStorage, NULL, 16);
  }

  All_ColorPallete[SliderToChange] = 
  {
    CRGBPalette16   (
                        HEX_VALUE[0], HEX_VALUE[1], HEX_VALUE[2],  HEX_VALUE[3], HEX_VALUE[4], HEX_VALUE[5], HEX_VALUE[6],  HEX_VALUE[7],
                        HEX_VALUE[8], HEX_VALUE[9], HEX_VALUE[10],  HEX_VALUE[11], HEX_VALUE[12], HEX_VALUE[13], HEX_VALUE[14],  HEX_VALUE[15]
                    )
  };

  needsUpdate = true;
}

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

  for (int i = 0; i > NUM_OF_BUTTONS; i++)
  {
    pinMode(Buttons[i], INPUT);
  }

  // FastLED.addLeds doesnt support arrays
  FastLED.addLeds<WS2812, 11, GRB>(leds[0], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 10, GRB>(leds[1], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 9, GRB>(leds[2], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 8, GRB>(leds[3], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 7, GRB>(leds[4], NUM_OF_LEDS_PER_STRIP);

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
          needsUpdate = true;
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
      FastLED.setBrightness(loadingValue/8);
      setLEDs(128, i);
    }
    FastLED.show();
  }
}

void loop()
{

  char c = Serial.read();
  if (c == 63)
  {
      Serial.println("mixlit");
      delay(200);
      needsUpdate = true;
  }

  stringToSendToSoftware = "";

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    //Serial.println("Reading Slider: " + String(i));
    currentSliderState[i] = 1023 - analogRead(Sliders[i]);
  }
  for (int i = 0; i < NUM_OF_POTENTIOMETERS; i++)
  {
    //Serial.println("Reading Slider: " + String(i));
    currentPotentiometerState[i] =  analogRead(Potentiometers[i]);
  }
  for (int i = 0; i < NUM_OF_BUTTONS; i++)
  {
    currentButtonState[i] = digitalRead(Buttons[i]);
    //Serial.println("Reading Button: " + String(i));
  }

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    if ((abs(currentSliderState[i] - previousSliderState[i]) > 3) || isAnimated || needsUpdate)
    {
      if (currentSliderState[i] > 1020)
      {
        currentSliderState[i] = 1023;
      }
      else if (currentSliderState[i] < 3)
      {
        currentSliderState[i] = 0;
      }

      setLEDs(currentSliderState[i], i);
    }

    if ((abs(currentSliderState[i] - previousSliderState[i]) > 3 || needsUpdate))
    {
      previousSliderState[i] = currentSliderState[i];
      stringToSendToSoftware += i;
      stringToSendToSoftware += "|";
      stringToSendToSoftware += previousSliderState[i];
      stringToSendToSoftware += "|";
    }
  }

  FastLED.show();

  needsUpdate = false;

  /*
  for (int i = 0; i < NUM_OF_POTENTIOMETERS; i++)
  {
    if ((abs(currentPotentiometerState[i] - previousPotentiometerState[i]) > 10))
    {
      if (currentPotentiometerState[i] > 1020)
      {
        currentPotentiometerState[i] = 1023;
      }
      else if (currentPotentiometerState[i] < 3)
      {
        currentPotentiometerState[i] = 0;
      }

      previousPotentiometerState[i] = currentPotentiometerState[i];
      stringToSendToSoftware += NUM_OF_SLIDERS + i;
      stringToSendToSoftware += "|";
      stringToSendToSoftware += previousPotentiometerState[i];
      stringToSendToSoftware += "|";
    }
  }
  */

  for (int i = 0; i < NUM_OF_BUTTONS; i++)
  {
    if (currentButtonState[i] != previousButtonState[i])
    {
      previousButtonState[i] = currentButtonState[i];

      stringToSendToSoftware += ButtonNames[i];
      stringToSendToSoftware += "|";
      stringToSendToSoftware += int(currentButtonState[i]);
      stringToSendToSoftware += "|";
    }
  }

  if (stringToSendToSoftware != "")
  {
    Serial.println(stringToSendToSoftware);
  }
}