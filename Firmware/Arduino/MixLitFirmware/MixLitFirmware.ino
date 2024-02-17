/*

MixLit Firmware V2

For Arduino

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

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
uint32_t HEX_VALUE = 0;

long currentMillis;
long lastMillis;

int loops = 0;

int colorIndexOffset;

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

CRGBPalette16 All_ColorPallete[NUM_OF_LED_STRIPS] = 
{
  CRGBPalette16   (
                    0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFF0000,  0xFF0000,
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
  needsUpdate = false;

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
  
  if (Serial.available() > 0) {
    // read the incoming byte:
    serialDataFromPC = Serial.readString();

    Serial.println("--------------------------------");
    Serial.println("");
    Serial.println("String Input:");
    Serial.println(serialDataFromPC);

    serialDataFromPC.toCharArray(tempFullHexStorage, 128);

    Serial.println("Temp Hex Storage:");
    Serial.println(tempFullHexStorage);
    Serial.println("");

    for (int i = 0; i < 6; i++)
    {
      tempPartHexStorage[i] = tempFullHexStorage[6+i];
    }

    HEX_VALUE = strtol(tempPartHexStorage, NULL, 16);
    
    Serial.println("HEX_VALUE:");
    Serial.println(HEX_VALUE, HEX);
    Serial.println("");
    Serial.println("--------------------------------");

    All_ColorPallete[0] = 
    {
      CRGBPalette16   (
                        HEX_VALUE, HEX_VALUE, HEX_VALUE,  HEX_VALUE, HEX_VALUE, HEX_VALUE, 0xFF0000,  0xFF0000,
                        0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                      )
    };

    needsUpdate = true;
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