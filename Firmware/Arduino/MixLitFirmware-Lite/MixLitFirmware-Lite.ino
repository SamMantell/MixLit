/*

MixLit Firmware V2

For Arduino Leonardo

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit Lite, this program will only use a MIDI interface for control so for use with VoiceMeter and Linux

*/

#include <MIDIUSB.h>

#define NUM_OF_SLIDERS 5

const int Sliders[NUM_OF_SLIDERS] = {A1, A2, A3, A4, A5};
int prevSliderState[NUM_OF_SLIDERS];
int SliderState[NUM_OF_SLIDERS];

bool needsUpdate = true;

void controlChange(byte channel, byte control, byte value) {
  midiEventPacket_t event = {0x0B, 0xB0 | channel, control, value};
  MidiUSB.sendMIDI(event);
}


void setup()
{

}

void loop()
{ 
  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    SliderState[i] = analogRead(Sliders[i]);

    if (abs(SliderState[i] - prevSliderState[i]) > 2)
    {
      prevSliderState[i] = SliderState[i];

      controlChange(1, i, (SliderState[i] >> 3));
      MidiUSB.flush();
    }
  }

  if (needsUpdate = true) needsUpdate = false;

  delay(20);
}
