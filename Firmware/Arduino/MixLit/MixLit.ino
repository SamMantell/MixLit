#include <Wire.h>
#include "Adafruit_MPR121.h"
#include "MIDIUSB.h"

#ifndef _BV
#define _BV(bit) (1 << (bit)) 
#endif

#define outputA 4
#define outputB 5

#define Slider_00 A0
#define Slider_01 A1
#define Slider_02 A2

int counter = 0; 
int aLastState0; 
int aLastState1;  
int aLastState2;  

bool SliderChanging = false;

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

void setup() {

  pinMode (outputA,INPUT);
  pinMode (outputB,INPUT);

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

  currtouched = cap.touched();
  
  for (uint8_t i=0; i<12; i++) {
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

  //
  // end of temp
  //

  SliderChanging = false;

  if ((analogRead(Slider_00) > aLastState0 + 1) || (analogRead(Slider_00) < aLastState0 - 1)){
    Serial.println("Pin 0 changed from " + String(aLastState0)  + " to " + (analogRead(Slider_00)));
    controlChange(1, 1, analogRead(Slider_00)/8);
    MidiUSB.flush();
    aLastState0 = analogRead(Slider_00);
    SliderChanging = true;
  }

  if ((analogRead(Slider_01) > aLastState1 + 1) || (analogRead(Slider_01) < aLastState1 - 1)){
    Serial.println("Pin 1 changed from " + String(aLastState1) + " to " + (analogRead(Slider_01)));
    controlChange(1, 2, analogRead(Slider_01)/8);
    MidiUSB.flush();
    aLastState1 = analogRead(Slider_01);
    SliderChanging = true;
  }

  if ((analogRead(Slider_02) > aLastState2 + 1) || (analogRead(Slider_02) < aLastState2 - 1)){
    Serial.println("Pin 2 changed from " + String(aLastState2) + " to " + (analogRead(Slider_02)));
    controlChange(1, 3, analogRead(Slider_02)/8);
    MidiUSB.flush();
    aLastState2 = analogRead(Slider_02);
    SliderChanging = true;
  }

  if (!SliderChanging){
    delay(10);
  }
}
