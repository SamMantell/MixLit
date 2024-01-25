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
  0xf0ebe4, 0xe6dcca, 0xd9c9a9, 0xdbc088, 0xe0bb70, 0xE0AA3E, 0xE0AA3E, 0xE0AA3E,
  /*This line is not used ->*/0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000
};

extern const TProgmemRGBPalette32 Others_WhiteColor_p FL_PROGMEM =
{
  0xFFEEEE, 0xFFBBBB, 0xFFAAAA, 0xFF8888, 0xFF6666, 0xFF4444, 0xFF2222, 0xFF0000,
  0xEEFFEE, 0xBBFFBB, 0xAAFFAA, 0x88FF88, 0x66FF66, 0x44FF44, 0x22FF22, 0x00FF00,
  0xEEEEFF, 0xBBBBFF, 0xAAAAFF, 0x8888FF, 0x6666FF, 0x4444FF, 0x2222FF, 0x0000FF,
  0xFFEEFF, 0xFFBBFF, 0xFFAAFF, 0xFF88FF, 0xFF66FF, 0xFF44FF, 0xFF22FF, 0xFF00FF
};

CRGBPalette16 Main_ColorPalette = Main_WhiteColor_p;
CRGBPalette32 Others_ColorPalette = Others_WhiteColor_p;

uint8_t MainColorIndex;
uint8_t OtherColorIndex;

void setLEDs(int iCurrentValue, uint8_t red, uint8_t green, uint8_t blue, int ledStrip)
{
  uint8_t iNumOfLedsOn = iCurrentValue >> 7;
  uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

  if (ledStrip == 0)
  {
    for (int i = 0; i < 8; i++)
    {
      MainColorIndex = 16*i;

      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, MainColorIndex, iFinalLedBrightness, LINEARBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, MainColorIndex, 255, LINEARBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( Main_ColorPalette, MainColorIndex, 0, LINEARBLEND);
    }
  }
  else
  {
    for (int i = 0; i < 8; i++)
    {
      OtherColorIndex = (ledStrip-1) * 64 + i * 8;

      if (i == (7 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( Others_ColorPalette, OtherColorIndex, iFinalLedBrightness, LINEARBLEND);
  
      else if (i > (7 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( Others_ColorPalette, OtherColorIndex, 255, LINEARBLEND);
      
      else                                leds[ledStrip][i] = ColorFromPalette( Others_ColorPalette, OtherColorIndex, 0, LINEARBLEND);
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
