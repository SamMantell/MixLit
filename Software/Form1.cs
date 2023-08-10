using System;
using System.Windows.Forms;
using System.IO.Ports;
using RJCP.IO.Ports;

namespace MixLit_Software
{
    public partial class Form1 : Form
    {
        private RJCP.IO.Ports.SerialPortStream serialPort;
        private TrackBar[] sliders;
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

        private void simulateButton_Click_1(object sender, EventArgs e)
        {
            string simulatedData = simtext.Text;

            try
            {
                serialPort.Write(simulatedData);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error sending simulated data: " + ex.Message);
            }
        }
    }
}