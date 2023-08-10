namespace MixLit_Software
{
    partial class Form1
    {
        /// <summary>
        ///  Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            slider0 = new TrackBar();
            slider1 = new TrackBar();
            slider2 = new TrackBar();
            slider3 = new TrackBar();
            slider4 = new TrackBar();
            SimulateText = new Label();
            simtext = new TextBox();
            simulateButton = new Button();
            ((System.ComponentModel.ISupportInitialize)slider0).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider1).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider2).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider3).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider4).BeginInit();
            SuspendLayout();
            // 
            // slider0
            // 
            slider0.Location = new Point(328, 100);
            slider0.Maximum = 1024;
            slider0.Name = "slider0";
            slider0.Size = new Size(104, 45);
            slider0.TabIndex = 0;
            slider0.TabStop = false;
            slider0.Scroll += slider0_Scroll;
            // 
            // slider1
            // 
            slider1.Location = new Point(328, 151);
            slider1.Maximum = 1024;
            slider1.Name = "slider1";
            slider1.Size = new Size(104, 45);
            slider1.TabIndex = 1;
            // 
            // slider2
            // 
            slider2.Location = new Point(328, 202);
            slider2.Maximum = 1024;
            slider2.Name = "slider2";
            slider2.Size = new Size(104, 45);
            slider2.TabIndex = 2;
            // 
            // slider3
            // 
            slider3.Location = new Point(328, 253);
            slider3.Maximum = 1024;
            slider3.Name = "slider3";
            slider3.Size = new Size(104, 45);
            slider3.TabIndex = 3;
            // 
            // slider4
            // 
            slider4.Location = new Point(328, 304);
            slider4.Maximum = 1024;
            slider4.Name = "slider4";
            slider4.Size = new Size(104, 45);
            slider4.TabIndex = 4;
            // 
            // SimulateText
            // 
            SimulateText.AutoSize = true;
            SimulateText.Location = new Point(656, 346);
            SimulateText.Name = "SimulateText";
            SimulateText.Size = new Size(58, 15);
            SimulateText.TabIndex = 5;
            SimulateText.Text = "Simulator";
            // 
            // simtext
            // 
            simtext.Location = new Point(656, 373);
            simtext.Name = "simtext";
            simtext.Size = new Size(100, 23);
            simtext.TabIndex = 6;
            // 
            // simulateButton
            // 
            simulateButton.Location = new Point(669, 402);
            simulateButton.Name = "simulateButton";
            simulateButton.Size = new Size(75, 23);
            simulateButton.TabIndex = 7;
            simulateButton.Text = "Simulate";
            simulateButton.UseVisualStyleBackColor = true;
            simulateButton.Click += simulateButton_Click_1;
            // 
            // Form1
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 450);
            Controls.Add(simulateButton);
            Controls.Add(simtext);
            Controls.Add(SimulateText);
            Controls.Add(slider4);
            Controls.Add(slider3);
            Controls.Add(slider2);
            Controls.Add(slider1);
            Controls.Add(slider0);
            Name = "Form1";
            Text = "Form1";
            ((System.ComponentModel.ISupportInitialize)slider0).EndInit();
            ((System.ComponentModel.ISupportInitialize)slider1).EndInit();
            ((System.ComponentModel.ISupportInitialize)slider2).EndInit();
            ((System.ComponentModel.ISupportInitialize)slider3).EndInit();
            ((System.ComponentModel.ISupportInitialize)slider4).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private TrackBar slider0;
        private TrackBar slider1;
        private TrackBar slider2;
        private TrackBar slider3;
        private TrackBar slider4;
        private Label SimulateText;
        private TextBox simtext;
        private Button simulateButton;
    }
}