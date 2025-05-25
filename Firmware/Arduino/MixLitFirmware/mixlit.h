#include <FastLED.h>
#include "definitions.h"

class mixlit {
  public:
    const int sliders[NUM_OF_SLIDERS] = {A4, A3, A2, A1, A0};
    const int potentiometers[NUM_OF_POTENTIOMETERS] = {A5, A7, A6};
    const int ledStrips[NUM_OF_LED_STRIPS] = {11, 10, 9, 8, 7};
    const int buttons[NUM_OF_BUTTONS] = {6, 5, 4, 3, 2};
    const String buttonNames[NUM_OF_BUTTONS] = {"A", "B", "C", "D", "E"};

    int previousSliderState[NUM_OF_SLIDERS];
    int currentSliderState[NUM_OF_SLIDERS];

    int currentPotentiometerState[NUM_OF_POTENTIOMETERS];
    int previousPotentiometerState[NUM_OF_POTENTIOMETERS];

    bool previousButtonState[NUM_OF_BUTTONS];
    bool currentButtonState[NUM_OF_BUTTONS];

    CRGB leds[NUM_OF_LED_STRIPS][NUM_OF_LEDS_PER_STRIP];

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

    int sliderToChange;
    bool needsUpdate;

    bool isConnected;

    String serialCommand;

    void setLEDs(int iCurrentValue, int ledStrip)
    {
      // if (isAnimated) colorIndexOffset++;

      // else colorIndexOffset = 0;

      // this will take the 10 bit value from the slider, and use bitshift and remainder calculation to get the number of leds on and the brightness of the final one.
      uint8_t iNumOfLedsOn = iCurrentValue >> 7;
      uint8_t iFinalLedBrightness = (iCurrentValue % 128) << 1;

      for (int i = 0; i < 8; i++)
      {
        ColorIndex = 16*i/* + colorIndexOffset*/;

        if (i == (NUM_OF_LEDS_PER_STRIP - 1 - iNumOfLedsOn))        leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, iFinalLedBrightness);
      
        else if (i > (NUM_OF_LEDS_PER_STRIP - 1 - iNumOfLedsOn))    leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, 255);
          
        else                                                        leds[ledStrip][i] = ColorFromPalette( All_ColorPallete[ledStrip], ColorIndex, 0);
      }
    }

    void serialHandler()
    {
      while (Serial.available() > 0)
      {
        char incomingChar = Serial.read();
        if (incomingChar != 10 && incomingChar != 63 && incomingChar != 33 && incomingChar != 32 && incomingChar != 9) serialCommand += incomingChar;
        if (incomingChar == 33)
        {
          if (serialCommand == "")
          {
            Serial.println("ping");
          }
          else
          {
            Serial.println(serialCommand);
            readDataSetLEDs(serialCommand);
            serialCommand = "";
          }
        }
      }
    }

    void readDataSetLEDs(String serialDataFromPC)
    {
      char tempFullHexStorage[128];
      char tempPartHexStorage[6];
      uint32_t HEX_VALUE[8];
      int SliderToChange;

      serialDataFromPC.toCharArray(tempFullHexStorage, 128);

      tempPartHexStorage[1] = 0;
      tempPartHexStorage[2] = 0;
      tempPartHexStorage[3] = 0;
      tempPartHexStorage[4] = 0;
      tempPartHexStorage[5] = 0;

      tempPartHexStorage[0] = tempFullHexStorage[0];
      HEX_VALUE[0] = strtoul(tempPartHexStorage, NULL, 16);
      SliderToChange = HEX_VALUE[0];

      Serial.println("setting led strip " + String(SliderToChange));

      tempPartHexStorage[0] = tempFullHexStorage[1];
      HEX_VALUE[0] = strtoul(tempPartHexStorage, NULL, 16);
      isAnimated = bool(HEX_VALUE[0]);

      for (int i = 0; i < 16; i++)
      {
        for (int j = 0; j < 6; j++)
        {
          tempPartHexStorage[j] = tempFullHexStorage[2+(6*i+j)];
          // Serial.println(tempPartHexStorage[j]);
        }
        // Serial.println(tempPartHexStorage);
        HEX_VALUE[i] = strtoul(tempPartHexStorage, NULL, 16);
        // Serial.println(HEX_VALUE[i]);
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
};