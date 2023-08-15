using System;
using System.Windows.Forms;
using System.IO.Ports;
using RJCP.IO.Ports;
using NAudio.CoreAudioApi;
using System.Linq;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Collections.Concurrent;
using System.Reflection.Emit;

namespace MixLit_Software
{
    public partial class Form1 : Form
    {
        private TrackBar[] sliders;
        private Dictionary<TrackBar, Tuple<Process, List<int>>> sliderProcesses = new Dictionary<TrackBar, Tuple<Process, List<int>>>();
        private Dictionary<TrackBar, FlowLayoutPanel> sliderBars = new Dictionary<TrackBar, FlowLayoutPanel>();
        private Process slider1Process;
        private Process slider2Process;
        private Process slider3Process;
        private Process slider4Process;
        private Process slider5Process;

        private System.Timers.Timer faderUpdateTimer;

        private Dictionary<TrackBar, bool> sliderChanging = new Dictionary<TrackBar, bool>();
        private System.Timers.Timer colorTransitionTimer = new System.Timers.Timer();
        private System.Timers.Timer rainbowEffectTimer = new System.Timers.Timer();
        private int rainbowColorIndex = 0;

        private const int AnimationInterval = 1;
        private const float EasingFactor = 0.1f;

        private bool isFollowingMouse = false;
        private Task animationTask;

        SerialPortStream serialPort = new SerialPortStream("COM11", 115200);

        private ConcurrentQueue<Tuple<TrackBar, int>> sliderUpdateQueue = new ConcurrentQueue<Tuple<TrackBar, int>>();
        private bool isProcessingQueue = false;

        private Color originalBackColor;
        private Color hoverBackColor = Color.FromArgb(100, 50, 50, 50);

        private Font originalFont;
        private Font hoverFont = new Font("Nevis", 30, FontStyle.Bold);

        public Form1()
        {
            InitializeComponent();

            closeAppLabel.Text = "X";
            closeAppLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            closeAppLabel.Font = new Font("Nevis", 28, FontStyle.Bold);
            closeAppLabel.ForeColor = Color.White;
            closeAppLabel.BackColor = Color.FromArgb(80, 30, 30, 30);
            closeAppLabel.Size = new Size(50, 50);
            closeAppLabel.Location = new Point((ClientSize.Width - closeAppLabel.Size.Width) - 10, 10);
            closeAppLabel.Visible = true;
            closeAppLabel.Anchor = AnchorStyles.Top;
            Controls.Add(closeAppLabel);

            this.MouseDown += Form1_MouseDown;
            this.MouseUp += Form1_MouseUp;

            sliders = new TrackBar[] { slider1, slider2, slider3, slider4, slider5 };

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
                slider.ValueChanged += Slider_Scroll;
                FlowLayoutPanel bar = CreateSliderBar();
                sliderBars[slider] = bar;
                bar.Visible = false;
                Controls.Add(bar);
                bar.SendToBack();
            }

            foreach (var slider in sliders)
            {
                sliderChanging[slider] = false;
            }

            colorTransitionTimer.Interval = 200;
            colorTransitionTimer.Start();
            colorTransitionTimer.Elapsed += ColorTransitionTimer_Tick;

            rainbowEffectTimer.Interval = 100;
            rainbowEffectTimer.Start();
            rainbowEffectTimer.Elapsed += RainbowEffectTimer_Tick;

            serialPort.DataReceived += SerialPort_DataReceived;

            closeAppLabel.MouseEnter += CloseAppLabel_MouseEnter;
            closeAppLabel.MouseLeave += CloseAppLabel_MouseLeave;

            originalBackColor = closeAppLabel.BackColor;
            originalFont = closeAppLabel.Font;

            try
            {
                serialPort.Open();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error opening serial port: " + ex.Message);
            }

            faderUpdateTimer = new System.Timers.Timer();
            faderUpdateTimer.Interval = 5;
            faderUpdateTimer.Elapsed += FaderUpdateTimer_Tick;
            faderUpdateTimer.Start();

        }

        private void FaderUpdateTimer_Tick(object sender, EventArgs e)
        {
            UpdateSliderValueAndExecuteEvent(slider1, fader1.Maximum - fader1.Value);
            UpdateSliderValueAndExecuteEvent(slider2, fader2.Maximum - fader2.Value);
            UpdateSliderValueAndExecuteEvent(slider3, fader3.Maximum - fader3.Value);
            UpdateSliderValueAndExecuteEvent(slider4, fader4.Maximum - fader4.Value);
            UpdateSliderValueAndExecuteEvent(slider5, fader5.Maximum - fader5.Value);
        }

        private void UpdateSliderValueAndExecuteEvent(TrackBar slider, int value)
        {
            value = Math.Min(slider.Maximum, Math.Max(slider.Minimum, value));

            slider.BeginInvoke(new Action(() =>
            {
                if (slider.Value != value)
                {
                    slider.Value = value;
                    Slider_Scroll(slider, EventArgs.Empty);
                }
            }));
        }

        private async void Form1_MouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {

                isFollowingMouse = true;

                if (animationTask == null || animationTask.IsCompleted)
                {
                    animationTask = AnimateGlideAsync();
                }
            }
        }

        private async void Form1_MouseUp(object sender, MouseEventArgs e)
        {

            isFollowingMouse = false;
            return;

        }

        private async Task AnimateGlideAsync()
        {
            while (isFollowingMouse)
            {
                await Task.Delay(AnimationInterval);

                Point targetPosition = Cursor.Position;
                Point currentPosition = this.Location;

                int targetX = targetPosition.X - (this.Width / 2);
                int targetY = targetPosition.Y - (this.Height / 2);

                int dx = (int)((targetX - currentPosition.X) * EasingFactor);
                int dy = (int)((targetY - currentPosition.Y) * EasingFactor);

                this.Invoke(new Action(() =>
                {
                    this.Location = new Point(currentPosition.X + dx, currentPosition.Y + dy);
                }));
            }
        }


        private async void ColorTransitionTimer_Tick(object sender, EventArgs e)
        {
            foreach (var slider in sliders)
            {
                if (sliderChanging[slider])
                {
                    await Task.Run(() =>
                    {
                        int sensorValue = slider.Value;
                        UpdateSliderBar(slider, sensorValue);
                    });
                }
            }
        }

        private async void RainbowEffectTimer_Tick(object sender, EventArgs e)
        {
            await Task.Run(() =>
            {
                rainbowColorIndex = (rainbowColorIndex + 1) % 360;
                Color rainbowColor = ColorFromHSV(rainbowColorIndex, 1, 1);

                foreach (var kvp in sliderBars)
                {
                    FlowLayoutPanel bar = kvp.Value;
                    bar.BackColor = rainbowColor;
                }
            });
        }

        private Color ColorFromHSV(int hue, double saturation, double value)
        {
            int hi = Convert.ToInt32(Math.Floor((double)hue / 60)) % 6;
            double f = (double)hue / 60 - Math.Floor((double)hue / 60);

            value = value * 255;
            int v = Convert.ToInt32(value);
            int p = Convert.ToInt32(value * (1 - saturation));
            int q = Convert.ToInt32(value * (1 - f * saturation));
            int t = Convert.ToInt32(value * (1 - (1 - f) * saturation));

            if (hi == 0)
                return Color.FromArgb(255, v, t, p);
            else if (hi == 1)
                return Color.FromArgb(255, q, v, p);
            else if (hi == 2)
                return Color.FromArgb(255, p, v, t);
            else if (hi == 3)
                return Color.FromArgb(255, p, q, v);
            else if (hi == 4)
                return Color.FromArgb(255, t, p, v);
            else
                return Color.FromArgb(255, v, p, q);
        }

        private FlowLayoutPanel CreateSliderBar()
        {
            FlowLayoutPanel bar = new FlowLayoutPanel();
            bar.BackColor = Color.Green;
            bar.Width = 64;
            bar.Margin = new Padding(5);
            return bar;
        }

        private void UpdateSliderBar(TrackBar slider, int sensorValue)
        {
            if (sliderBars.TryGetValue(slider, out FlowLayoutPanel bar))
            {
                float heightPercentage = (float)sensorValue / slider.Maximum + 0.1f;

                if (sliderChanging[slider])
                {
                    int redValue = (int)(255 * heightPercentage);
                    int greenValue = 255 - redValue;

                    // Marshaling UI update to the UI thread
                    BeginInvoke(new Action(() =>
                    {
                        bar.BackColor = Color.FromArgb(redValue, greenValue, 0);
                    }));
                }
                else
                {
                    int maxHeight = slider.Height - (bar.Margin.Top + bar.Margin.Bottom) + 10;

                    // Marshaling UI update to the UI thread
                    BeginInvoke(new Action(() =>
                    {
                        int newHeight = (int)EaseInOutCubic(slider.Value, 0, maxHeight, slider.Maximum);
                        bar.Height = newHeight;
                        int topOffset = (slider.Height - bar.Height);
                        bar.Top = slider.Top + topOffset;
                        bar.Left = (slider.Left + slider.Width + bar.Margin.Left) - slider.Width - 15;
                    }));
                }
            }
        }

        private float EaseInOutCubic(float t, float b, float c, float d)
        {
            t /= d / 2;
            if (t < 1) return c / 2 * t * t * t + b;
            t -= 2;
            return c / 2 * (t * t * t + 2) + b;
        }

        private async void Slider_Scroll(object sender, EventArgs e)
        {
            TrackBar slider = sender as TrackBar;
            if (slider != null)
            {
                sliderChanging[slider] = false;

                int sensorValue = slider.Value;

                await Task.Run(() =>
                {
                    UpdateSliderBar(slider, sensorValue);
                });

                if (sliderBars.TryGetValue(slider, out FlowLayoutPanel bar))
                {
                    bar.Visible = true;
                }

                AdjustVolumeForSlider(slider, sensorValue);
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
                    if (sliderBars.TryGetValue(sliders[i], out FlowLayoutPanel bar))
                    {
                        // Use a different thread for UI control to seperate functionality and feedback for responsiveness hopefully
                        bar.BeginInvoke(new Action(() => bar.Visible = true));
                    }

                    sliders[i].BeginInvoke(new Action(() =>
                    {
                        sliders[i].Value = sensorValue;
                        Slider_Scroll(sliders[i], EventArgs.Empty);
                    }));

                    Thread.Sleep(10);
                }
            }
        }

        private void AdjustVolumeForSlider(TrackBar slider, int sensorValue)
        {
            try
            {
                float sliderValue = (float)sensorValue / 1024;
                MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                MMDevice defaultDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);

                var sessions = defaultDevice.AudioSessionManager.Sessions;

                var sliderProcessTuple = sliderProcesses[slider];
                Process sliderProcess = sliderProcessTuple.Item1;

                if (sliderProcess != null)
                {
                    var processIds = sliderProcessTuple.Item2;

                    for (int i = 0; i < sessions.Count; i++)
                    {
                        var session = sessions[i];
                        if (processIds.Contains((int)session.GetProcessID))
                        {
                            session.SimpleAudioVolume.Volume = sliderValue;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex.ToString());
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
            slider1.Enabled = true;

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
            slider2.Enabled = true;

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
            slider3.Enabled = true;

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
            slider4.Enabled = true;

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
            slider5.Enabled = true;

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

        private void closeAppLabel_Click(object sender, EventArgs e)
        {
            serialPort.Close();
            this.Close();
        }

        private async void CloseAppLabel_MouseEnter(object sender, EventArgs e)
        {
            await AnimateLabelAppearance(closeAppLabel, hoverBackColor, hoverFont);
        }

        private async void CloseAppLabel_MouseLeave(object sender, EventArgs e)
        {
            await AnimateLabelAppearance(closeAppLabel, originalBackColor, originalFont);
        }

        private async Task AnimateLabelAppearance(System.Windows.Forms.Label label, Color targetBackColor, Font targetFont)
        {
            const int AnimationDuration = 200;
            const int AnimationSteps = 20;

            Color startColor = label.BackColor;
            Font startFont = label.Font;

            for (int step = 1; step <= AnimationSteps; step++)
            {
                float interpolationRatio = (float)step / AnimationSteps;
                Color interpolatedColor = InterpolateColor(startColor, targetBackColor, interpolationRatio);
                Font interpolatedFont = InterpolateFont(startFont, targetFont, interpolationRatio);

                label.BackColor = interpolatedColor;
                label.Font = interpolatedFont;

                await Task.Delay(AnimationDuration / AnimationSteps);
            }

            label.BackColor = targetBackColor;
            label.Font = targetFont;
        }

        private Color InterpolateColor(Color startColor, Color endColor, float interpolationRatio)
        {
            int r = (int)Math.Round(startColor.R + (endColor.R - startColor.R) * interpolationRatio);
            int g = (int)Math.Round(startColor.G + (endColor.G - startColor.G) * interpolationRatio);
            int b = (int)Math.Round(startColor.B + (endColor.B - startColor.B) * interpolationRatio);

            return Color.FromArgb(r, g, b);
        }

        private Font InterpolateFont(Font startFont, Font endFont, float interpolationRatio)
        {
            float newSize = startFont.Size + (endFont.Size - startFont.Size) * interpolationRatio;
            return new Font(startFont.FontFamily, newSize, endFont.Style);
        }
    }
}