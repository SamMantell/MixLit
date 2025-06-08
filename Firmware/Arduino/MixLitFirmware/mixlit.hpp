#include <FastLED.h>
#include "definitions.h"

#include <List.hpp>

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

    int sliderToChange;
    bool needsUpdate;

    bool isConnected;

    String serialCommand;
    List<String> serialCommandBuffer;

    uint8_t loadingValue = 0;
    bool loadingUp = true;

    uint32_t HEX_VALUE[16];
    int SliderToChange;

    String stringToSendToSoftware = "";

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

    void setLEDs(int iCurrentValue, int ledStrip)
    {
      if (isAnimated)
      {
        colorIndexOffset++;
      }
      else
      {
        colorIndexOffset = 0;
      }

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
      if (isAnimated) delay(5);
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
            //Serial.println(serialCommand);
            serialCommandBuffer.add(serialCommand);
            //Serial.println(serialCommandBuffer.get(0));
            // readDataSetLEDs(serialCommand);
            serialCommand = "";
          }
        }
      }
      
      while (serialCommandBuffer.getSize() != 0)
      {
        readDataSetLEDs(serialCommandBuffer.get(0));
        // Serial.println(serialCommandBuffer.get(0));
        serialCommandBuffer.removeFirst();
      }
    }

    void readDataSetLEDs(String serialDataFromPC)
    {
      // Serial.println(serialDataFromPC);
      
      SliderToChange = strtol(serialDataFromPC.substring(0,1).c_str(), NULL, 16);
      isAnimated = bool(strtol(serialDataFromPC.substring(1,2).c_str(), NULL, 16));
      // Serial.println("setting led strip " + String(SliderToChange) + " and setting animation to " + String (isAnimated));

      for (int i = 0; i < 16; i++)
      {
        HEX_VALUE[i] = strtol(serialDataFromPC.substring(2+i*6, 8+i*6).c_str(), NULL, 16);
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

    void initialize()
    {
      Serial.begin(38400);

      for (int i = 0; i > NUM_OF_SLIDERS; i++)          pinMode(sliders[i], INPUT);
      for (int i = 0; i > NUM_OF_POTENTIOMETERS; i++)   pinMode(potentiometers[i], INPUT);
      for (int i = 0; i > NUM_OF_BUTTONS; i++)          pinMode(buttons[i], INPUT);

      FastLED.addLeds<WS2812, 11, GRB>(leds[0], NUM_OF_LEDS_PER_STRIP);
      FastLED.addLeds<WS2812, 10, GRB>(leds[1], NUM_OF_LEDS_PER_STRIP);
      FastLED.addLeds<WS2812, 9, GRB>(leds[2], NUM_OF_LEDS_PER_STRIP);
      FastLED.addLeds<WS2812, 8, GRB>(leds[3], NUM_OF_LEDS_PER_STRIP);
      FastLED.addLeds<WS2812, 7, GRB>(leds[4], NUM_OF_LEDS_PER_STRIP);
    }

    void awaitConnection()
    {
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

    void readStates()
    {
      for (int i = 0; i < NUM_OF_SLIDERS; i++)
      {
        currentSliderState[i] = 1023 - analogRead(sliders[i]);
      }
      for (int i = 0; i < NUM_OF_POTENTIOMETERS; i++)
      {
        currentPotentiometerState[i] =  analogRead(potentiometers[i]);
      }
      for (int i = 0; i < NUM_OF_BUTTONS; i++)
      {
        currentButtonState[i] = digitalRead(buttons[i]);
      }
    }

    void denoiseAndBuildString()
    {
      stringToSendToSoftware = "";

      for (int i = 0; i < NUM_OF_SLIDERS; i++)
      {
        if ((abs(currentSliderState[i] - previousSliderState[i]) > 5) || needsUpdate)
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

        if ((abs(currentSliderState[i] - previousSliderState[i]) > 5))
        {
          previousSliderState[i] = currentSliderState[i];
          stringToSendToSoftware += i;
          stringToSendToSoftware += "|";
          stringToSendToSoftware += previousSliderState[i];
          stringToSendToSoftware += "|";
        }
      }

      for (int i = 0; i < NUM_OF_BUTTONS; i++)
      {
        if (currentButtonState[i] != previousButtonState[i])
        {
          previousButtonState[i] = currentButtonState[i];

          stringToSendToSoftware += buttonNames[i];
          stringToSendToSoftware += "|";
          stringToSendToSoftware += int(currentButtonState[i]);
          stringToSendToSoftware += "|";
        }
      }
    }
};