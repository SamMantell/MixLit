using System;
using System.Windows.Forms;
using System.IO.Ports;
using RJCP.IO.Ports;
using NAudio.CoreAudioApi;
using System.Linq;
using System.Diagnostics;

namespace MixLit_Software
{
    public partial class Form1 : Form
    {
        private RJCP.IO.Ports.SerialPortStream serialPort;
        private TrackBar[] sliders;
        private Dictionary<TrackBar, Tuple<Process, List<int>>> sliderProcesses = new Dictionary<TrackBar, Tuple<Process, List<int>>>();
        private MMDeviceEnumerator deviceEnumerator;
        private Process slider1Process;
        private Process slider2Process;
        private Process slider3Process;
        private Process slider4Process;
        private Process slider5Process;

        public Form1()
        {
            InitializeComponent();

            sliders = new TrackBar[] { slider1, slider2, slider3, slider4, slider5 };

            serialPort = new SerialPortStream("COM11", 115200);
            serialPort.DataReceived += SerialPort_DataReceived;
            try
            {
                serialPort.Open();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error opening serial port: " + ex.Message);
            }

            MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
            MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            var sessions = defaultDevice.AudioSessionManager.Sessions;

            for (int i = 0; i < sessions.Count; i++)
            {
                var session = sessions[i];
                var processId = session.GetProcessID;

                foreach (var slider in sliders)
                {
                    Process sliderProcess = Process.GetProcessById((int)processId);
                    if (sliderProcess != null)
                    {
                        ComboBox appSelect = GetAppSelectComboBox(slider);
                        appSelect.Items.Add(sliderProcess.ProcessName);
                        if (!sliderProcesses.ContainsKey(slider))
                        {
                            sliderProcesses[slider] = new Tuple<Process, List<int>>(sliderProcess, new List<int>());
                        }
                        sliderProcesses[slider].Item2.Add(sliderProcess.Id);
                    }
                }
            }

            foreach (var slider in sliders)
            {
                slider.Scroll += Slider_Scroll;
            }
        }

        private void Slider_Scroll(object sender, EventArgs e)
        {
            TrackBar slider = sender as TrackBar;
            if (slider != null)
            {
                int sliderIndex = Array.IndexOf(sliders, slider);
                int sensorValue = slider.Value;
                AdjustVolumeForSlider(sliderIndex, sensorValue);
            }
        }

        private ComboBox GetAppSelectComboBox(TrackBar slider)
        {
            if (slider == slider1)
                return Slider1AppSelect;
            else if (slider == slider2)
                return slider2AppSelect;
            else if (slider == slider3)
                return slider3AppSelect;
            else if (slider == slider4)
                return slider4AppSelect;
            else if (slider == slider5)
                return slider5AppSelect;
            else
                return null;
        }

        private void SerialPort_DataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            string data = serialPort.ReadLine();
            string[] sliderValues = data.Split('|');

            for (int i = 0; i < sliderValues.Length - 1; i++)
            {
                if (i < sliders.Length && int.TryParse(sliderValues[i], out int sensorValue))
                {
                    BeginInvoke(new Action(() =>
                    {
                        sliders[i].Value = sensorValue;
                        // Adjust volume based on the received sensor value
                        AdjustVolumeForSlider(i, sensorValue);
                    }));
                }
            }
        }

        private void AdjustVolumeForSlider(int sliderIndex, int sensorValue)
        {
            try
            {
                float sliderValue = (float)sensorValue / sliders[sliderIndex].Maximum;
                MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                // Iterate through all sliderProcesses and adjust volume for matching sessions
                foreach (var kvp in sliderProcesses)
                {
                    TrackBar slider = kvp.Key;
                    Process sliderProcess = kvp.Value.Item1;

                    if (sliderProcess != null)
                    {
                        int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                        for (int i = 0; i < sessionCount; i++)
                        {
                            var session = defaultDevice.AudioSessionManager.Sessions[i];
                            if (kvp.Value.Item2.Contains((int)session.GetProcessID))
                            {
                                session.SimpleAudioVolume.Volume = sliderValue;
                                break;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Write(ex.ToString());
            }
        }

        private Process GetSliderProcess(int sliderIndex)
        {
            switch (sliderIndex)
            {
                case 0:
                    return slider1Process;
                case 1:
                    return slider2Process;
                case 2:
                    return slider3Process;
                case 3:
                    return slider4Process;
                case 4:
                    return slider5Process;
                default:
                    return null;
            }
        }

        private void slider1_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (slider1Process != null)
                {
                    float sliderValue = (float)slider1.Value / slider1.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == slider1Process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex) { }
        }

        private void slider2_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (slider2Process != null)
                {
                    float sliderValue = (float)slider2.Value / slider2.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == slider2Process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex) { MessageBox.Show("exception: " + ex.Message); }
        }

        private void slider3_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (slider3Process != null)
                {
                    float sliderValue = (float)slider3.Value / slider3.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == slider3Process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex) { MessageBox.Show("exception: " + ex.Message); }
        }

        private void slider4_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (slider4Process != null)
                {
                    float sliderValue = (float)slider4.Value / slider4.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == slider4Process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex) { MessageBox.Show("exception: " + ex.Message); }
        }

        private void slider5_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (slider5Process != null)
                {
                    float sliderValue = (float)slider5.Value / slider5.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == slider5Process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex) { MessageBox.Show("exception: " + ex.Message); }
        }

        private void Slider1AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = Slider1AppSelect.SelectedItem.ToString();
            slider1Process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            slider1AppName.Text = slider1Process.ProcessName;

            if (slider1Process != null)
            {
                try
                {
                    Icon appIcon = Icon.ExtractAssociatedIcon(slider1Process.MainModule.FileName);
                    slider1Icon.SizeMode = PictureBoxSizeMode.CenterImage;
                    slider1Icon.Image = appIcon.ToBitmap();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error getting icon: " + ex.Message);
                }
            }
            else
            {
                slider1Icon.SizeMode = PictureBoxSizeMode.Normal;
                slider1Icon.Image = null;
            }
        }

        private void slider2AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = slider2AppSelect.SelectedItem.ToString();
            slider2Process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            slider2AppName.Text = slider2Process.ProcessName;

            if (slider2Process != null)
            {
                try
                {
                    Icon appIcon = Icon.ExtractAssociatedIcon(slider2Process.MainModule.FileName);
                    slider2Icon.SizeMode = PictureBoxSizeMode.CenterImage;
                    slider2Icon.Image = appIcon.ToBitmap();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error getting icon: " + ex.Message);
                }
            }
            else
            {
                slider2Icon.SizeMode = PictureBoxSizeMode.Normal;
                slider2Icon.Image = null;
            }
        }

        private void slider3AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = slider3AppSelect.SelectedItem.ToString();
            slider3Process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            slider3AppName.Text = slider3Process.ProcessName;

            if (slider3Process != null)
            {
                try
                {
                    Icon appIcon = Icon.ExtractAssociatedIcon(slider3Process.MainModule.FileName);
                    slider3Icon.SizeMode = PictureBoxSizeMode.CenterImage;
                    slider3Icon.Image = appIcon.ToBitmap();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error getting icon: " + ex.Message);
                }
            }
            else
            {
                slider3Icon.SizeMode = PictureBoxSizeMode.Normal;
                slider3Icon.Image = null;
            }
        }

        private void slider4AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = slider4AppSelect.SelectedItem.ToString();
            slider4Process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            slider4AppName.Text = slider4Process.ProcessName;

            if (slider4Process != null)
            {
                try
                {
                    Icon appIcon = Icon.ExtractAssociatedIcon(slider4Process.MainModule.FileName);
                    slider4Icon.SizeMode = PictureBoxSizeMode.CenterImage;
                    slider4Icon.Image = appIcon.ToBitmap();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error getting icon: " + ex.Message);
                }
            }
            else
            {
                slider4Icon.SizeMode = PictureBoxSizeMode.Normal;
                slider4Icon.Image = null;
            }
        }

        private void slider5AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = slider5AppSelect.SelectedItem.ToString();
            slider5Process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            slider5AppName.Text = slider5Process.ProcessName;

            if (slider5Process != null)
            {
                try
                {
                    Icon appIcon = Icon.ExtractAssociatedIcon(slider5Process.MainModule.FileName);
                    slider5Icon.SizeMode = PictureBoxSizeMode.CenterImage;
                    slider5Icon.Image = appIcon.ToBitmap();
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Error getting icon: " + ex.Message);
                }
            }
            else
            {
                slider5Icon.SizeMode = PictureBoxSizeMode.Normal;
                slider5Icon.Image = null;
            }
        }
    }
}