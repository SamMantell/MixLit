#include <Wire.h>
#include "Adafruit_MPR121.h"
#include "MIDIUSB.h"

#ifndef _BV
#define _BV(bit) (1 << (bit)) 
#endif

const int Sliders[3] = {A0, A1, A2};

int SliderState[3];

Adafruit_MPR121 cap = Adafruit_MPR121();

uint16_t lasttouched = 0;
uint16_t currtouched = 0;

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

bool SliderChanged(int Slider, int SliderValue, int SliderPrevValue){
  return ((SliderValue < SliderPrevValue - 1) || (SliderValue > SliderPrevValue + 1));
}

void setup() {

  Serial.begin(115200);

  while (!Serial) {
    delay(10);
  }

  if (!cap.begin(0x5A)) {
    Serial.println("MPR121 not found, check wiring?");
    while (1);
  }

  Serial.println("MPR121 found!");
}

void loop() {

  //
  // This is tempary for buttons!
  //

  /*
  currtouched = cap.touched();
  
  for (uint8_t i = 0; i < 12; i++) {
    if ((currtouched & _BV(i)) && !(lasttouched & _BV(i)) ) {
      Serial.print(i); Serial.println(" touched");
      if (i == 1){
        noteOn(0, 48, 64);
        MidiUSB.flush();
      }
      if (i == 2){
        noteOn(0, 49, 64);
        MidiUSB.flush();
      }
    }
    if (!(currtouched & _BV(i)) && (lasttouched & _BV(i)) ) {
      Serial.print(i); Serial.println(" released");
      if (i == 1){
        noteOff(0, 48, 64);
        MidiUSB.flush();
      }
      if (i == 2){
        noteOff(0, 49, 64);
        MidiUSB.flush();
      }
    }
  }

  lasttouched = currtouched;

  */

  //
  // end of temp
  //
  for (int i = 0; i < 3; i++){
    if (SliderChanged(i, analogRead(Sliders[i]), SliderState[i])){
      //Serial.println("Slider " + String(i) + " Changed from " + String(SliderState[i]) + " to " + String(analogRead(Sliders[i])));
      SliderState[i] = analogRead(Sliders[i]);
      controlChange(1, i, int(SliderState[i]/8));
      //Serial.println("controlChange(1, " + String(i) + ", " + String(int(SliderState[i]/8)) + ")");
      MidiUSB.flush();
    }
  }
  
  delay(10);
}
