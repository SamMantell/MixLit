#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include "MIDIUSB.h"

#ifdef __AVR__
#endif

#define PIN 3
#define NUMPIXELS 4

Adafruit_NeoPixel pixels(NUMPIXELS, PIN, NEO_GRB + NEO_KHZ800);

const int NumOfSliders = 5;
const int Sliders[NumOfSliders] = {A0, A1, A2, A3, A4};

bool deej = false;

int SliderState[NumOfSliders];

int NumToSendToVoiceMeter;
float VoiceMeterOutput;

void noteOn(byte channel, byte pitch, byte velocity) {
  midiEventPacket_t noteOn = {0x09, 0x90 | channel, pitch, velocity};
  MidiUSB.sendMIDI(noteOn);
}

void noteOff(byte channel, byte pitch, byte velocity) {
  midiEventPacket_t noteOff = {0x08, 0x80 | channel, pitch, velocity};
  MidiUSB.sendMIDI(noteOff);
}

void controlChange(byte channel, byte control, byte value) {
  // First parameter is the event type (0x0B = control change).
  // Second parameter is the event type, combined with the channel.
  // Third parameter is the control number number (0-119).
  // Fourth parameter is the control value (0-127).
  midiEventPacket_t event = {0x0B, 0xB0 | channel, control, value};
  MidiUSB.sendMIDI(event);
}

void RoundTo(float num, int dp) {
  float number = num * 10;
  number = int(number);
  number = float(number / 10);
  return number;
}



void setLEDs(float MaxVal, float CurrentVal, int Red, int Green, int Blue, int MaxBrightness, int StartingLED, int EndingLED) {
  pixels.clear();
  pixels.setBrightness(MaxBrightness);
  float Range = EndingLED - StartingLED;
  float Value = CurrentVal/MaxVal;
  float NumOfLEDsOnFloat = Range * Value;
  int NumOfLEDsOn = int(Range * Value);
  float FinalLEDBrightness = NumOfLEDsOnFloat - NumOfLEDsOn;

  for (int i = StartingLED; i < StartingLED + NumOfLEDsOn + 1; i++){
    if (i < StartingLED + NumOfLEDsOn){
      pixels.setPixelColor(i, pixels.Color(Red, Green, Blue));
    }
    else{
      pixels.setPixelColor(i, pixels.Color(Red * FinalLEDBrightness, Green * FinalLEDBrightness, Blue * FinalLEDBrightness));
    }
    pixels.show();
  }
}


bool SliderChanged(int Slider, int SliderValue, int SliderPrevValue){
  return ((SliderValue < SliderPrevValue - 4) || (SliderValue > SliderPrevValue + 4));
}

void setup() {
  pixels.begin();

  Serial.begin(115200);

  while (!Serial) {
    delay(10);
  }
}

void loop() {
  for (int i = 0; i < NumOfSliders; i++){
    if (SliderChanged(i, analogRead(Sliders[i]), SliderState[i])){
      //Serial.println("Slider " + String(i) + " Changed from " + String(SliderState[i]) + " to " + String(analogRead(Sliders[i])));
      SliderState[i] = analogRead(Sliders[i]);

      if (!deej) {
        NumToSendToVoiceMeter = 127 - int(SliderState[i])/8;
        controlChange(1, i, NumToSendToVoiceMeter);
        //Serial.println("controlChange(1, " + String(i) + ", " + String(127 - int(SliderState[i]/8)) + ")");
        //Serial.println(float(round(VoiceMeterOutput*10))/10);
        VoiceMeterOutput = (127 - int(SliderState[i]/8)) * 0.5669 - 60;
        MidiUSB.flush();
      }
      else {
        String builtString = String("");

        for (int i = 0; i < NumOfSliders; i++) {
          
          if (i==5){
            builtString += String((int)SliderState[i]);
          }
          else{
            builtString += String((int)SliderState[i]);
          }

          if (i < NumOfSliders - 1) {
            builtString += String("|");
          }
        }

        Serial.println(builtString);
      }

      if (i==1){
        setLEDs(1024, SliderState[i], 255, 255, 255, 255, 0, 4);
      }
    }
  }
  
  delay(50);
}
