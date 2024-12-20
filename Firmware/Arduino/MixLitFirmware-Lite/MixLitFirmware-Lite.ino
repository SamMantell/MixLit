/*

MixLit Firmware V2

For Arduino Leonardo

Authors: Sam Mantell, Goddeh
GitHub: @SamMantell, @Goddeh1

This program is the firmware for the MixLit Lite, this program will only use a MIDI interface for control so for use with VoiceMeter and Linux

*/

#define NUM_OF_SLIDERS 5

const int Sliders[NUM_OF_SLIDERS] = {A4, A3, A2, A1, A0};
int prevSliderState[NUM_OF_SLIDERS];
int SliderState[NUM_OF_SLIDERS];

bool needsUpdate = true;

void setup()
{
  Serial.begin(115200);
  while (!Serial)
  {
    delay(10);
  }
}

void loop()
{ 
  String builtString = String("");

  for (int i = 0; i < NUM_OF_SLIDERS; i++)
  {
    SliderState[i] = 1024 - analogRead(Sliders[i]);

    if (abs(SliderState[i] - prevSliderState[i]) > 10)
    {
      prevSliderState[i] = SliderState[i];

      builtString += String(i) + "|" + String(SliderState[i]) + "|";
    }
  }

  if (builtString != "") Serial.println(builtString);

  if (needsUpdate = true) needsUpdate = false;

  delay(20);
}
