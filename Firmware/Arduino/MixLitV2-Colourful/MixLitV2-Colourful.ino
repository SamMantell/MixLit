/*

MixLit Firmware V2

For Arduino

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

*/

#include <Wire.h>
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

void setLEDs(int iCurrentValue, uint8_t red, uint8_t green, uint8_t blue, int ledStrip)
{
  uint16_t NewColorIndex = colorIndex + ledStrip*2;
  uint8_t iNumOfLedsOn = iCurrentValue >> 7;
  uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

  for (int i = 0; i < 8; i++)
  {
    if (i == (7 - iNumOfLedsOn))
    {
      leds[ledStrip][i] = ColorFromPalette( OceanColors_p , NewColorIndex, iFinalLedBrightness, LINEARBLEND);
      //leds[ledStrip][i] = CRGB(iFinalLedBrightness, iFinalLedBrightness, iFinalLedBrightness);
    }
    else if (i > (7 - iNumOfLedsOn))
    {
      leds[ledStrip][i] = ColorFromPalette( OceanColors_p , NewColorIndex, 255, LINEARBLEND);
      //leds[ledStrip][i] = CRGB(red, green, blue);
    }
    else
    {
      leds[ledStrip][i] = ColorFromPalette( OceanColors_p , NewColorIndex, 0, LINEARBLEND);
      //leds[ledStrip][i] = CRGB(0, 0, 0);
    }
  }

  FastLED.show();
}

void controlChange(byte channel, byte control, byte value) {
  // First parameter is the event type (0x0B = control change).
  // Second parameter is the event type, combined with the channel.
  // Third parameter is the control number number (0-119).
  // Fourth parameter is the control value (0-127).
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