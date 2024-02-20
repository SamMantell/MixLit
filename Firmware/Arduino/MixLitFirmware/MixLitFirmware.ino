/*

MixLit Firmware V2

For Arduino Leonardo

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit, it is responsible for taking slider inputs, sending them to a PC over serial.

It also is responsible for control over the LEDS, these can be adjusted over serial by sending a string to the MixLit over serial as follows.



      0     0      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF       FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      |     |                               |                                                         |
 Slider ID  |   First set of HEX RGB values for the 8 leds on the strip     Second set of 8 values for if it is animated
            |
  Wether it is animated



RGB values are sent as 24 bits over 6 HEX values, the brightness of the LED can be controled by the RGB value, master brightness and the brightness used in the function to control the brightness of the final LED lit.

*/

#include <FastLED.h>
#include <MIDIUSB.h>

#ifdef __AVR__
#endif

#define NUM_OF_LED_STRIPS 5
#define NUM_OF_SLIDERS 5
#define NUM_OF_LEDS_PER_STRIP 8

String serialDataFromPC;

const int Sliders[NUM_OF_LED_STRIPS] = {A1, A2, A3, A4, A5};
int prevSliderState[NUM_OF_LED_STRIPS];
int SliderState[NUM_OF_LED_STRIPS];

bool isAnimated = false;
bool isVoiceMeter = true;
bool needsUpdate = true;

char tempFullHexStorage[128];
char tempPartHexStorage[128];

uint32_t HEX_VALUE[8];
int SliderToChange;

long currentMillis;
long lastMillis;

int loops = 0;

int colorIndexOffset;

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

CRGBPalette16 All_ColorPallete[NUM_OF_LED_STRIPS] = 
{
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFF0000, 0xFF0000,  0xFF0000,
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

uint8_t ColorIndex;
uint8_t OtherColorIndex;

void setLEDs(int iCurrentValue, int ledStrip)
{
  if (isAnimated) colorIndexOffset++;

  else colorIndexOffset = 0;

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

void controlChange(byte channel, byte control, byte value) {
  midiEventPacket_t event = {0x0B, 0xB0 | channel, control, value};
  MidiUSB.sendMIDI(event);
}


void setup()
{

  if (!isVoiceMeter)
  {
    while (!Serial)
    {
    delay(10);
    }
  }

  //Wired the LEDs wrong should be 7, 6, 5, 4, 3 but here you can fix if need
  FastLED.addLeds<WS2812, 7, GRB>(leds[0], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 5, GRB>(leds[1], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 6, GRB>(leds[2], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 4, GRB>(leds[3], NUM_OF_LEDS_PER_STRIP);
  FastLED.addLeds<WS2812, 3, GRB>(leds[4], NUM_OF_LEDS_PER_STRIP);

  FastLED.setBrightness(24);
}

void loop()
{ 
  String builtString = String("");

  for (int i = 0; i < NUM_OF_LED_STRIPS; i++)
  {
    SliderState[i] = analogRead(Sliders[i]);

    if ((abs(SliderState[i] - prevSliderState[i]) > 2) || isAnimated || needsUpdate)
    {
      setLEDs(SliderState[i], i);
      FastLED.show();
    }

    if (abs(SliderState[i] - prevSliderState[i]) > 2)
    {
      prevSliderState[i] = SliderState[i];

      if (isVoiceMeter)
      {
        controlChange(1, i, (SliderState[i] >> 3));
        MidiUSB.flush();
      }
      else
      {
        builtString = String(i) + "|" + String(SliderState[i]);
        Serial.println(builtString);
      }
    }
  }

  if (needsUpdate = true) needsUpdate = false;
  
  if (Serial.available() > 0)
  {
    readSerialDataAndSetLEDs();
  }

  /*
  // Optimisation Check
  loops++;

  long currentMillis = millis() - lastMillis;
  if (loops == 100)
  {
    lastMillis += currentMillis;
    loops = 0;
    Serial.println(currentMillis);
  }
  */
  
}