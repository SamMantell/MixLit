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
        private Process process;
        public Form1()
        {
            InitializeComponent();

            sliders = new TrackBar[] { slider0, slider1, slider2, slider3, slider4 };

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
            process = Process.GetProcessById((int)processId);
            if (process != null)
            {
               Slider1AppSelect.Items.Add(process.ProcessName);
            }
            }
            }

        private void SerialPort_DataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            string data = serialPort.ReadLine();
            string[] sliderValues = data.Split('|');

            for (int i = 0; i < sliderValues.Length; i++)
            {
                if (i < sliders.Length && int.TryParse(sliderValues[i], out int sensorValue))
                {
                    BeginInvoke(new Action(() =>
                    {
                        sliders[i].Value = sensorValue;
                    }));
                }
            }
        }

        private void slider0_Scroll(object sender, EventArgs e)
        {
            try
            {
                if (process != null)
                {
                    float sliderValue = (float)slider0.Value / slider0.Maximum;

                    MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                    MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                    int sessionCount = defaultDevice.AudioSessionManager.Sessions.Count;
                    for (int i = 0; i < sessionCount; i++)
                    {
                        var session = defaultDevice.AudioSessionManager.Sessions[i];
                        if (session.GetProcessID == process.Id)
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                            break;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error adjusting volume: " + ex.Message);
            }
        }

        private void slider1_Scroll(object sender, EventArgs e)
        {
        }

        private void slider2_Scroll(object sender, EventArgs e)
        {
        }

        private void slider3_Scroll(object sender, EventArgs e)
        {
        }

        private void slider4_Scroll(object sender, EventArgs e)
        {
        }

        private void slider2_Scroll_1(object sender, EventArgs e)
        {

        }
        private void Slider1AppSelect_SelectedIndexChanged(object sender, EventArgs e)
        {
            string selectedAppName = Slider1AppSelect.SelectedItem.ToString();
            process = Process.GetProcessesByName(selectedAppName)
                            .FirstOrDefault();

            if (process != null)
            {
                MessageBox.Show("Selected process: " + process.ProcessName);
            }
            else
            {
                MessageBox.Show("Process not found or not suitable for volume control: " + selectedAppName);
            }
        }

        private List<string> GetRunningApplicationNames()
        {
            List<string> appNames = new List<string>();

            Process[] processes = Process.GetProcesses();

            appNames = processes
                .Where(p => p.MainWindowHandle != IntPtr.Zero && p.WorkingSet64 > 1024 * 1024)
                .Select(p => p.ProcessName)
                .Distinct()
                .ToList();

            return appNames;
        }
    }
}