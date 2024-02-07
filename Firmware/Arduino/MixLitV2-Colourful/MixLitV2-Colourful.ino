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
#define NUM_OF_LEDS_PER_STRIP 8

const int NumOfSliders = 5;
char SliderIDs[NumOfSliders] = {'A', 'A', 'A', 'A', 'A'};
const int Sliders[NumOfSliders] = {A1, A2, A3, A4, A5};
int prevSliderState[NumOfSliders];
int SliderState[NumOfSliders];

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

CRGBPalette16 Main_ColorPalette = CRGBPalette16   (
                /* Controls LED Strip 1 ! */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFF0000,  0xFF0000,
                /* This line is redundant */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF
                                                  );

CRGBPalette16 Second_ColorPalette = CRGBPalette16 (
                /* Controls LED Strip 2 ! */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFF0000,  0xFF0000,
                /* Controls LED Strip 3 ! */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x00FF00,  0x00FF00
                                                  );

CRGBPalette16 Third_ColorPalette = CRGBPalette16  (
                /* Controls LED Strip 4 ! */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x0000FF,  0x0000FF,
                /* Controls LED Strip 5 ! */      0xFFFFFF, 0xFFFFFF, 0xFFFFFF,  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFF00FF,  0xFF00FF
                                                  );

uint8_t ColorIndex;
uint8_t OtherColorIndex;

void setLEDs(int iCurrentValue, uint8_t red, uint8_t green, uint8_t blue, int ledStrip)
{
  uint8_t iNumOfLedsOn = iCurrentValue >> 7;
  uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

  if (ledStrip == 0)
  {
    for (int i = 0; i < 8; i++)
    {
      ColorIndex = 16*i;

      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, ColorIndex, iFinalLedBrightness, NOBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, ColorIndex, 255, NOBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, ColorIndex, 0, NOBLEND);
    }
  }
  else if (ledStrip == 1 || ledStrip == 2)
  {
    for (int i = 0; i < 8; i++)
    {
      ColorIndex = 16*i+(ledStrip-1)*128;

      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( Second_ColorPalette, ColorIndex, iFinalLedBrightness, NOBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( Second_ColorPalette, ColorIndex, 255, NOBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( Second_ColorPalette, ColorIndex, 0, NOBLEND);
    }
  }
  else
  {
    for (int i = 0; i < 8; i++)
    {
      ColorIndex = 16*i+(ledStrip-3)*128;

      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( Third_ColorPalette, ColorIndex, iFinalLedBrightness, NOBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( Third_ColorPalette, ColorIndex, 255, NOBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( Third_ColorPalette, ColorIndex, 0, NOBLEND);
    }
  }

  FastLED.show();
}

void controlChange(byte channel, byte control, byte value) {
  midiEventPacket_t event = {0x0B, 0xB0 | channel, control, value};
  MidiUSB.sendMIDI(event);
}


void setup()
{

  /*

  while (!Serial) {
    delay(10);
  }

  */

  //Wired the LEDs wrong should be 7, 6, 5, 4, 3
  FastLED.addLeds<NEOPIXEL, 7>(leds[0], NUM_OF_LEDS_PER_STRIP).setCorrection( TypicalLEDStrip );
  FastLED.addLeds<NEOPIXEL, 5>(leds[1], NUM_OF_LEDS_PER_STRIP).setCorrection( TypicalLEDStrip );
  FastLED.addLeds<NEOPIXEL, 6>(leds[2], NUM_OF_LEDS_PER_STRIP).setCorrection( TypicalLEDStrip );
  FastLED.addLeds<NEOPIXEL, 4>(leds[3], NUM_OF_LEDS_PER_STRIP).setCorrection( TypicalLEDStrip );
  FastLED.addLeds<NEOPIXEL, 3>(leds[4], NUM_OF_LEDS_PER_STRIP).setCorrection( TypicalLEDStrip );

  FastLED.setBrightness(32);
}

void loop()
{
  String builtString = String("");

  for (int i = 0; i < NumOfSliders; i++)
  {

    SliderState[i] = analogRead(Sliders[i]);

    int diff = abs(SliderState[i] - prevSliderState[i]);

    setLEDs(SliderState[i], 10, 10, 10, i);

    if (diff > 2)
    {
      prevSliderState[i] = SliderState[i];

      builtString += String(SliderIDs[i]) + String(i + 1) + "|" + String(SliderState[i]);

      if (i != NumOfSliders - 1)
      {
        builtString += String("|");
      }

      controlChange(1, i, (SliderState[i] >> 3));
      MidiUSB.flush();
    }
  }

  delay(20);
}