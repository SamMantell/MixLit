#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include "MIDIUSB.h"

#ifdef __AVR__
#endif

#define PIN 3
#define NUMPIXELS 4

Adafruit_NeoPixel pixels(NUMPIXELS, PIN, NEO_GRB + NEO_KHZ800);

const int Sliders[3] = {A0, A1, A2};

int SliderState[3];

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


void setLEDs(int MaxVal, int CurrentVal, int Red, int Green, int Blue, int MaxBrightness, int StartingLED, int EndingLED) {
  pixels.clear();
  pixels.setBrightness(MaxBrightness);
  int Range = EndingLED - StartingLED;
  float Value = float(float(CurrentVal)/float(MaxVal));
  Serial.println(Value);
  float NumOfLEDsOnFloat = float(float(Range * Value));
  int NumOfLEDsOn = int(float(Range * Value));
  float FinalLEDBrightness = float (NumOfLEDsOnFloat - NumOfLEDsOn);

  Serial.println(NumOfLEDsOn);
  Serial.println(FinalLEDBrightness);

  for (int i = StartingLED; i < StartingLED + NumOfLEDsOn + 1; i++){
    if (i < StartingLED + NumOfLEDsOn){
      pixels.setPixelColor(i, pixels.Color(Red, Green, Blue));
      pixels.show();
    }
    else{
      pixels.setPixelColor(i, pixels.Color(Red * FinalLEDBrightness, Green * FinalLEDBrightness, Blue * FinalLEDBrightness));
      pixels.show();
    }
  }
}


bool SliderChanged(int Slider, int SliderValue, int SliderPrevValue){
  return ((SliderValue < SliderPrevValue - 1) || (SliderValue > SliderPrevValue + 1));
}

void setup() {

  Serial.begin(115200);

  pixels.begin();

  while (!Serial) {
    delay(10);
  }
}

void loop() {
  for (int i = 0; i < 3; i++){
    if (SliderChanged(i, analogRead(Sliders[i]), SliderState[i])){
      //Serial.println("Slider " + String(i) + " Changed from " + String(SliderState[i]) + " to " + String(analogRead(Sliders[i])));
      SliderState[i] = analogRead(Sliders[i]);
      controlChange(1, i, SliderState[i]/8);
      //Serial.println("controlChange(1, " + String(i) + ", " + String(int(SliderState[i]/8)) + ")");
      MidiUSB.flush();

      if (i==1){
        setLEDs(1024, SliderState[i], 255, 255, 255, 128, 1, 4);
      }
    }
  }
  
  delay(10);
}
