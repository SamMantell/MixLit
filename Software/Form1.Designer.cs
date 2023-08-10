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
            sliderApp1 = new Label();
            Slider1AppSelect = new ComboBox();
            ((System.ComponentModel.ISupportInitialize)slider0).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider1).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider2).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider3).BeginInit();
            ((System.ComponentModel.ISupportInitialize)slider4).BeginInit();
            SuspendLayout();
            // 
            // slider0
            // 
            slider0.BackColor = SystemColors.ControlDark;
            slider0.CausesValidation = false;
            slider0.Cursor = Cursors.No;
            slider0.LargeChange = 0;
            slider0.Location = new Point(219, 108);
            slider0.Maximum = 1024;
            slider0.Name = "slider0";
            slider0.Orientation = Orientation.Vertical;
            slider0.RightToLeft = RightToLeft.No;
            slider0.Size = new Size(45, 248);
            slider0.SmallChange = 0;
            slider0.TabIndex = 0;
            slider0.TabStop = false;
            slider0.TickStyle = TickStyle.Both;
            slider0.Scroll += slider0_Scroll;
            // 
            // slider1
            // 
            slider1.BackColor = SystemColors.ControlDark;
            slider1.CausesValidation = false;
            slider1.Cursor = Cursors.No;
            slider1.LargeChange = 0;
            slider1.Location = new Point(282, 108);
            slider1.Maximum = 1024;
            slider1.Name = "slider1";
            slider1.Orientation = Orientation.Vertical;
            slider1.RightToLeft = RightToLeft.No;
            slider1.Size = new Size(45, 248);
            slider1.SmallChange = 0;
            slider1.TabIndex = 1;
            slider1.TickStyle = TickStyle.Both;
            // 
            // slider2
            // 
            slider2.BackColor = SystemColors.ControlDark;
            slider2.CausesValidation = false;
            slider2.Cursor = Cursors.No;
            slider2.LargeChange = 0;
            slider2.Location = new Point(350, 108);
            slider2.Maximum = 1024;
            slider2.Name = "slider2";
            slider2.Orientation = Orientation.Vertical;
            slider2.RightToLeft = RightToLeft.No;
            slider2.Size = new Size(45, 248);
            slider2.SmallChange = 0;
            slider2.TabIndex = 2;
            slider2.TickStyle = TickStyle.Both;
            slider2.Scroll += slider2_Scroll_1;
            // 
            // slider3
            // 
            slider3.BackColor = SystemColors.ControlDark;
            slider3.CausesValidation = false;
            slider3.Cursor = Cursors.No;
            slider3.LargeChange = 0;
            slider3.Location = new Point(419, 108);
            slider3.Maximum = 1024;
            slider3.Name = "slider3";
            slider3.Orientation = Orientation.Vertical;
            slider3.RightToLeft = RightToLeft.No;
            slider3.Size = new Size(45, 248);
            slider3.SmallChange = 0;
            slider3.TabIndex = 3;
            slider3.TickStyle = TickStyle.Both;
            // 
            // slider4
            // 
            slider4.BackColor = SystemColors.ControlDark;
            slider4.CausesValidation = false;
            slider4.Cursor = Cursors.No;
            slider4.LargeChange = 0;
            slider4.Location = new Point(488, 108);
            slider4.Maximum = 1024;
            slider4.Name = "slider4";
            slider4.Orientation = Orientation.Vertical;
            slider4.RightToLeft = RightToLeft.No;
            slider4.Size = new Size(45, 248);
            slider4.SmallChange = 0;
            slider4.TabIndex = 4;
            slider4.TickStyle = TickStyle.Both;
            // 
            // sliderApp1
            // 
            sliderApp1.AutoSize = true;
            sliderApp1.BackColor = Color.Transparent;
            sliderApp1.Font = new Font("nevis", 18F, FontStyle.Bold, GraphicsUnit.Point);
            sliderApp1.Location = new Point(198, 69);
            sliderApp1.Name = "sliderApp1";
            sliderApp1.RightToLeft = RightToLeft.No;
            sliderApp1.Size = new Size(92, 27);
            sliderApp1.TabIndex = 5;
            sliderApp1.Text = "Spotify";
            // 
            // Slider1AppSelect
            // 
            Slider1AppSelect.FormattingEnabled = true;
            Slider1AppSelect.Location = new Point(181, 362);
            Slider1AppSelect.Name = "Slider1AppSelect";
            Slider1AppSelect.Size = new Size(121, 23);
            Slider1AppSelect.TabIndex = 6;
            Slider1AppSelect.SelectedIndexChanged += Slider1AppSelect_SelectedIndexChanged;
            // 
            // Form1
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 450);
            Controls.Add(Slider1AppSelect);
            Controls.Add(sliderApp1);
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
        private Label sliderApp1;
        private ComboBox Slider1AppSelect;
    }
}