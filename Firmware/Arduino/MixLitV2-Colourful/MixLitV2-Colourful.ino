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

uint16_t colorIndex = 0;

const int NumOfSliders = 5;
char SliderIDs[NumOfSliders] = {'A', 'A', 'A', 'A', 'A'};
const int Sliders[NumOfSliders] = {A1, A2, A3, A4, A5};
int prevSliderState[NumOfSliders];
int SliderState[NumOfSliders];

int red = 0;
int green = 0;
int blue = 0;

CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

extern const TProgmemRGBPalette16 Main_WhiteColor_p FL_PROGMEM =
{
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF
};

extern const TProgmemRGBPalette32 Others_WhiteColor_p FL_PROGMEM =
{
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF
};

CRGBPalette16 Main_ColorPalette = Main_WhiteColor_p;
CRGBPalette32 Others_ColorPalette = Others_WhiteColor_p;

CRGBPalette16 MainColorPaletteToUse;
CRGBPalette32 OthersColorPaletteToUse;

void setLEDs(int iCurrentValue, uint8_t red, uint8_t green, uint8_t blue, int ledStrip)
{
  uint16_t NewColorIndex = colorIndex + ledStrip*51;
  uint8_t iNumOfLedsOn = iCurrentValue >> 7;
  uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

  if (ledStrip == 0)
  {
    for (int i = 0; i < 8; i++)
    {
      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( MainColorPaletteToUse , NewColorIndex, iFinalLedBrightness, LINEARBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( MainColorPaletteToUse , NewColorIndex, 255, LINEARBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( MainColorPaletteToUse , NewColorIndex, 0, LINEARBLEND);
    }
  }
  else
  {
    for (int i = 0; i < 8; i++)
    {
      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( OthersColorPaletteToUse , NewColorIndex, iFinalLedBrightness, LINEARBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( OthersColorPaletteToUse , NewColorIndex, 255, LINEARBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( OthersColorPaletteToUse , NewColorIndex, 0, LINEARBLEND);
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

  while (!Serial) {
    delay(10);
  }

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

  if (builtString.length() > 0)
  {
    Serial.println(builtString);
  }

  delay(20);
  colorIndex++;
}
