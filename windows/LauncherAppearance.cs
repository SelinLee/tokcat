using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// A single, in-memory desktop blur covers the whole launcher and its feathered
// margins. Native edit controls stay in place when the skin changes, preserving IME.
public sealed class TokcatLauncherAppearance : IDisposable
{
    readonly TokcatLauncherWindow window;
    readonly TokcatLauncherBackdrop halo = new TokcatLauncherBackdrop();
    readonly Timer timer = new Timer { Interval = 450 };
    readonly TokcatRadialBackdropCapture radialCapture = new TokcatRadialBackdropCapture();
    TokcatRadialBackdropCapture.Frame radialFrame;
    IntPtr[] radialHandles = new IntPtr[0];
    bool radialCapturing;
    Color fogTarget;
    double fogRed, fogGreen, fogBlue;
    long fogUpdatedAt;
    Bitmap backdrop;
    bool cyber, automatic, excluded;
    bool transparency = true;
    bool? light;
    public bool IsCyber { get { return cyber; } }
    public bool IsRadial { get; private set; }
    public bool IsLight { get { return light ?? window.ClassicIsLight; } }
    public int MarginX { get { return IsRadial ? 0 : (int)Math.Round(16 * window.LayoutScale); } }
    public int MarginY { get { return IsRadial ? 0 : (int)Math.Round(26 * window.LayoutScale); } }
    public Color Foreground { get { return IsLight ? Color.FromArgb(10, 36, 43) : Color.FromArgb(232, 255, 245); } }
    public Color Secondary { get { return IsLight ? Color.FromArgb(31, 64, 69) : Color.FromArgb(196, 240, 224); } }
    public Color Accent { get { return IsLight ? Color.FromArgb(5, 77, 74) : Color.FromArgb(120, 255, 209); } }
    public Color Pink { get { return IsLight ? Color.FromArgb(143, 26, 99) : Color.FromArgb(255, 148, 204); } }
    public Color Surface { get; private set; }
    public int BackgroundRevision { get; private set; }

    [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr handle, uint affinity);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();

    public TokcatLauncherAppearance(TokcatLauncherWindow window)
    {
        this.window = window;
        Surface = window.BackColor;
        timer.Tick += delegate { Capture(); };
        window.VisibleChanged += delegate
        {
            if (!window.Visible) { timer.Stop(); StopRadialCapture(); halo.Hide(); ReleaseImage(); SetWindowDisplayAffinity(window.Handle, 0); excluded = false; }
        };
        window.LocationChanged += delegate { if (window.Visible && cyber) halo.Hide(); };
        window.ResizeEnd += delegate { if (window.Visible && cyber && !IsRadial && excluded) Capture(); };
        window.SizeChanged += delegate { if (window.Visible && cyber && !IsRadial && excluded) Capture(); };
    }

    public void Configure(string skin, bool autoTextColor)
    {
        timer.Stop(); StopRadialCapture(); halo.Hide(); ReleaseImage();
        SetWindowDisplayAffinity(window.Handle, 0); excluded = false;
        IsRadial = skin == "radial" && !SystemInformation.HighContrast;
        cyber = (skin == "cyber" || IsRadial) && !SystemInformation.HighContrast;
        automatic = autoTextColor;
        light = null;
        transparency = Convert.ToInt32(Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 1)) != 0;
        Surface = IsLight ? Color.FromArgb(235, 248, 244) : Color.FromArgb(20, 32, 38);
        fogTarget = Surface; fogRed = Surface.R; fogGreen = Surface.G; fogBlue = Surface.B; fogUpdatedAt = System.Diagnostics.Stopwatch.GetTimestamp();
        window.ApplyColors();
    }

    public void Prepare()
    {
        if (!cyber || window.IsPreview) return;
        // Older systems turn exclusion into a black rectangle. Only capture through
        // a visible launcher on Windows 10 2004+, after both exclusions succeed.
        int build;
        object raw = Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuildNumber", "0");
        excluded = int.TryParse(Convert.ToString(raw), out build) && build >= 19041 &&
            SetWindowDisplayAffinity(window.Handle, 0x11) && SetWindowDisplayAffinity(halo.Handle, 0x11);
        SetWindowDisplayAffinity(window.Handle, 0); SetWindowDisplayAffinity(halo.Handle, 0);
        if (IsRadial) excluded = excluded && window.Radial.SetCaptureAffinity(0x11);
        if (IsRadial) window.Radial.SetCaptureAffinity(0);
        if (IsRadial && excluded && transparency)
        {
            radialHandles = window.Radial.CaptureHandles;
            radialCapture.Begin(); radialCapturing = true;
            QueueRadialCapture(true); return;
        }
        if (IsRadial) return;
        Capture();
    }

    public void Presented()
    {
        if (!cyber || window.IsPreview) return;
        if (IsRadial) { window.Radial.Present(); return; }
        ShowHalo();
        if (excluded && transparency) timer.Start();
    }

    public void UpdateBrightness(double brightness)
    {
        double cutoff = light.HasValue ? (light.Value ? 0.16 : 0.23) : 0.19;
        light = brightness >= cutoff;
    }

    void QueueRadialCapture(bool force)
    {
        if (!radialCapturing) return;
        radialCapture.Enqueue(window.Bounds, SystemInformation.VirtualScreen, Surface, radialHandles, force);
    }

    public bool PollRadialBackground()
    {
        if (!IsRadial || window.IsPreview || !window.Visible || !radialCapturing) return false;
        QueueRadialCapture(false);
        var next = radialCapture.TakeLatest();
        bool before = IsLight;
        if (next != null)
        {
            if (radialFrame != null) radialFrame.Dispose(); radialFrame = next;
            if (automatic) UpdateBrightness(next.Luminance);
            Color tint = IsLight ? Color.FromArgb(239,252,248) : Color.FromArgb(12,24,30);
            fogTarget = Color.FromArgb((next.Color.R * 105 + tint.R * 150) / 255, (next.Color.G * 105 + tint.G * 150) / 255, (next.Color.B * 105 + tint.B * 150) / 255);
        }
        long now = System.Diagnostics.Stopwatch.GetTimestamp();
        double elapsed = Math.Min(0.1, (now - fogUpdatedAt) / (double)System.Diagnostics.Stopwatch.Frequency); fogUpdatedAt = now;
        double step = 1 - Math.Exp(-elapsed / 0.12);
        fogRed += (fogTarget.R - fogRed) * step; fogGreen += (fogTarget.G - fogGreen) * step; fogBlue += (fogTarget.B - fogBlue) * step;
        Color color = Color.FromArgb((int)Math.Round(fogRed), (int)Math.Round(fogGreen), (int)Math.Round(fogBlue));
        bool changed = Surface != color;
        if (changed) { Surface = color; BackgroundRevision++; }
        if (before != IsLight) window.ApplyColors();
        return changed || before != IsLight;
    }

    void StopRadialCapture()
    {
        radialCapturing = false; radialCapture.Stop();
        foreach (var handle in radialHandles) SetWindowDisplayAffinity(handle, 0);
        radialHandles = new IntPtr[0];
    }

    public void PaintDesktop(Graphics graphics, Rectangle target, Rectangle screen)
    {
        using (var brush = new SolidBrush(Surface)) graphics.FillRectangle(brush, target);
    }

    void Capture()
    {
        if (!cyber || window.IsPreview || !transparency || window.IsDisposed || (window.Visible && !excluded)) return;
        try
        {
            if (window.Visible)
            {
                if (!SetWindowDisplayAffinity(window.Handle, 0x11) || !SetWindowDisplayAffinity(halo.Handle, 0x11) || (IsRadial && !window.Radial.SetCaptureAffinity(0x11))) { timer.Stop(); return; }
                DwmFlush();
            }
            var rectangle = new Rectangle(window.Left - MarginX, window.Top - MarginY,
                window.Width + MarginX * 2, window.Height + MarginY * 2);
            using (var source = new Bitmap(rectangle.Width, rectangle.Height))
            {
                using (var graphics = Graphics.FromImage(source))
                {
                    graphics.Clear(window.ClassicIsLight ? Color.WhiteSmoke : Color.FromArgb(25, 28, 32));
                    var visible = Rectangle.Intersect(rectangle, SystemInformation.VirtualScreen);
                    if (!visible.IsEmpty) graphics.CopyFromScreen(visible.Location, new Point(visible.X - rectangle.X, visible.Y - rectangle.Y), visible.Size);
                }
                RenderSource(source);
            }
            window.ApplyColors(); window.Invalidate(true);
            if (window.Visible) ShowHalo();
        }
        catch (Exception error)
        {
            if (!(error is System.ComponentModel.Win32Exception) && !(error is ExternalException) && !(error is ArgumentException)) throw;
            timer.Stop(); halo.Hide(); ReleaseImage(); window.ApplyColors();
        }
        finally { SetWindowDisplayAffinity(window.Handle, 0); SetWindowDisplayAffinity(halo.Handle, 0); if (IsRadial) window.Radial.SetCaptureAffinity(0); }
    }

    void RenderSource(Bitmap source)
    {
        double brightness = 0;
        int samples = 0;
        var sample = IsRadial ? new Rectangle((int)(source.Width / 2 - 80 * window.Radial.Scale), (int)(source.Height / 2 - 84 * window.Radial.Scale), (int)(160 * window.Radial.Scale), (int)(20 * window.Radial.Scale)) : new Rectangle(MarginX, MarginY, source.Width - 2 * MarginX, source.Height - 2 * MarginY);
        sample.Intersect(new Rectangle(Point.Empty, source.Size));
        for (int x = sample.Left; x < sample.Right; x += 10)
            for (int y = sample.Top; y < sample.Bottom; y += 10)
            {
                Color c = source.GetPixel(x, y);
                brightness += 0.2126 * Linear(c.R) + 0.7152 * Linear(c.G) + 0.0722 * Linear(c.B); samples++;
            }
        if (automatic && samples > 0) UpdateBrightness(brightness / samples);
        using (var small = new Bitmap(Math.Max(1, source.Width / 16), Math.Max(1, source.Height / 16)))
        {
            using (var g = Graphics.FromImage(small)) { g.InterpolationMode = InterpolationMode.HighQualityBilinear; g.DrawImage(source, new Rectangle(Point.Empty, small.Size)); }
            var next = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(next))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(small, new Rectangle(Point.Empty, next.Size));
                using (var tint = new SolidBrush(Color.FromArgb(150, IsLight ? Color.FromArgb(239, 252, 248) : Color.FromArgb(12, 24, 30)))) g.FillRectangle(tint, 0, 0, next.Width, next.Height);
            }
            ReleaseImage(); backdrop = next;
            Surface = Color.FromArgb(255, backdrop.GetPixel(backdrop.Width / 2, Math.Min(backdrop.Height - 1, IsRadial ? Math.Max(0, backdrop.Height / 2 - (int)(74 * window.Radial.Scale)) : MarginY + window.InputHeight / 2)));
        }
    }

    public void UsePreviewBackground(Bitmap source)
    {
        if (!window.IsPreview || !cyber || !transparency) return;
        if (IsRadial)
        {
            Color color = TokcatRadialBackdropCapture.Average(source);
            var sample = new TokcatRadialBackdropCapture.Frame(color, new Rectangle(Point.Empty, source.Size));
            if (automatic) UpdateBrightness(sample.Luminance);
            Color tint = IsLight ? Color.FromArgb(239,252,248) : Color.FromArgb(12,24,30);
            Surface = Color.FromArgb((color.R * 105 + tint.R * 150) / 255, (color.G * 105 + tint.G * 150) / 255, (color.B * 105 + tint.B * 150) / 255);
            ReleaseImage(); window.ApplyColors(); return;
        }
        RenderSource(source); window.ApplyColors();
    }

    static double Linear(byte channel) { double value = channel / 255.0; return value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4); }

    public void Paint(Graphics graphics, Rectangle target, Point origin)
    {
        if (IsRadial && radialFrame != null)
        {
            PaintDesktop(graphics, target, new Rectangle(window.Left + origin.X, window.Top + origin.Y, target.Width, target.Height)); return;
        }
        using (var brush = new SolidBrush(Surface)) graphics.FillRectangle(brush, target);
        if (backdrop != null) graphics.DrawImage(backdrop, target,
            new Rectangle(origin.X + MarginX, origin.Y + MarginY, target.Width, target.Height), GraphicsUnit.Pixel);
    }

    void ShowHalo()
    {
        if (IsRadial) { window.Radial.Invalidate(); return; }
        if (backdrop == null) return;
        using (var feather = CreateFeatheredMargins())
            halo.Update(feather, new Point(window.Left - MarginX, window.Top - MarginY), window.Handle);
    }

    public Bitmap CreateFeatheredMargins()
    {
        if (!cyber || IsRadial || backdrop == null) return null;
        var feather = new Bitmap(backdrop.Width, backdrop.Height, PixelFormat.Format32bppArgb);
        for (int y = 0; y < feather.Height; y++)
            for (int x = 0; x < feather.Width; x++)
            {
                if (x >= MarginX && x < feather.Width - MarginX && y >= MarginY && y < feather.Height - MarginY) continue;
                double horizontal = Math.Min(1, Math.Min(x, feather.Width - 1 - x) / (double)Math.Max(1, MarginX));
                double vertical = Math.Min(1, Math.Min(y, feather.Height - 1 - y) / (double)Math.Max(1, MarginY));
                double alpha = horizontal * vertical; alpha = alpha * alpha * (3 - 2 * alpha);
                feather.SetPixel(x, y, Color.FromArgb((int)(255 * alpha), backdrop.GetPixel(x, y)));
            }
        return feather;
    }

    void ReleaseImage() { BackgroundRevision++; if (backdrop != null) { backdrop.Dispose(); backdrop = null; } if (radialFrame != null) { radialFrame.Dispose(); radialFrame = null; } }
    public void Dispose() { timer.Stop(); timer.Dispose(); StopRadialCapture(); radialCapture.Dispose(); halo.Dispose(); ReleaseImage(); }
}

sealed class TokcatLauncherBackdrop : Form
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct Blend { public byte Operation, Flags, Alpha, Format; }
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr window, IntPtr destination, ref Point point, ref Size size, IntPtr source, ref Point origin, int key, ref Blend blend, int flags);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get { var p = base.CreateParams; p.ExStyle |= 0x80000 | 0x20 | 0x08000000 | 0x80; return p; }
    }
    public TokcatLauncherBackdrop() { FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual; }
    public void Update(Bitmap image, Point point, IntPtr launcher)
    {
        IntPtr dc = CreateCompatibleDC(IntPtr.Zero), bitmap = image.GetHbitmap(Color.FromArgb(0)), previous = SelectObject(dc, bitmap);
        try
        {
            Size size = image.Size; Point origin = Point.Empty;
            var blend = new Blend { Alpha = 255, Format = 1 };
            UpdateLayeredWindow(Handle, IntPtr.Zero, ref point, ref size, dc, ref origin, 0, ref blend, 2);
            if (!Visible) Show();
            SetWindowPos(Handle, launcher, 0, 0, 0, 0, 0x0010 | 0x0001 | 0x0002);
        }
        finally { SelectObject(dc, previous); DeleteObject(bitmap); DeleteDC(dc); }
    }
}

class TokcatLauncherSurfacePanel : Panel
{
    public TokcatLauncherWindow Launcher;
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0133 || message.Msg == 0x0138)
        {
            var editor = Control.FromHandle(message.LParam) as TokcatLauncherTextBox;
            if (editor != null)
            {
                IntPtr brush = editor.PaintBackground(message.WParam);
                if (brush != IntPtr.Zero) { message.Result = brush; return; }
            }
        }
        base.WndProc(ref message);
    }
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        if (Launcher != null && Launcher.Appearance != null && Launcher.Appearance.IsRadial) e.Graphics.Clear(TokcatLauncherRadial.TransparentKey);
        else if (Launcher != null && Launcher.Appearance != null && Launcher.Appearance.IsCyber)
            Launcher.Appearance.Paint(e.Graphics, ClientRectangle, Location);
        else base.OnPaintBackground(e);
    }
}

sealed class TokcatLauncherInputPanel : TokcatLauncherSurfacePanel
{
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (Launcher == null || Launcher.Appearance == null || !Launcher.Appearance.IsCyber || Launcher.Appearance.IsRadial) return;
        int inset = (int)(14 * Launcher.LayoutScale);
        using (var line = new LinearGradientBrush(new Rectangle(inset, Height - 2, Math.Max(1, Width - 2 * inset), 2), Launcher.Appearance.Accent, Color.Transparent, 0f))
            e.Graphics.FillRectangle(line, inset, Height - 2, Width - 2 * inset, Math.Max(1, (int)Launcher.LayoutScale));
        using (var pink = new SolidBrush(Launcher.Appearance.IsLight ? Color.FromArgb(143, 26, 99) : Color.FromArgb(255, 148, 204)))
            e.Graphics.FillRectangle(pink, inset, Height - 2, (int)(44 * Launcher.LayoutScale), Math.Max(1, (int)Launcher.LayoutScale));
    }
}

public sealed class TokcatLauncherTextBox : TextBox
{
    public TokcatLauncherWindow Launcher;
    public bool Composing { get; private set; }
    public string CompositionText { get; private set; }
    public int CompositionStart { get; private set; }
    public int CompositionCaret { get; private set; }
    int compositionSelection;
    bool candidateComposition;
    Keys compositionKeyDown;
    public string DisplayText
    {
        get
        {
            if (!Composing || string.IsNullOrEmpty(CompositionText)) return Text;
            int start = Math.Min(TextLength, CompositionStart);
            return Text.Substring(0, start) + CompositionText + Text.Substring(Math.Min(TextLength, start + compositionSelection));
        }
    }
    public event EventHandler CompositionChanged;
    public Action<Graphics, Rectangle, Point> BackgroundPainter;
    public int BackgroundVersion;
    IntPtr backgroundBrush, backgroundBitmap;
    int backgroundRevision = -1;
    Point backgroundOrigin;
    Size backgroundSize;

    [DllImport("gdi32.dll")] static extern IntPtr CreatePatternBrush(IntPtr bitmap);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] static extern int SetBkMode(IntPtr dc, int mode);
    [DllImport("gdi32.dll")] static extern int SetTextColor(IntPtr dc, int color);
    [DllImport("gdi32.dll")] static extern bool SetBrushOrgEx(IntPtr dc, int x, int y, IntPtr previous);
    [DllImport("imm32.dll")] static extern IntPtr ImmGetContext(IntPtr handle);
    [DllImport("imm32.dll")] static extern bool ImmReleaseContext(IntPtr handle, IntPtr context);
    [DllImport("imm32.dll", EntryPoint = "ImmGetCompositionStringW")] static extern int ImmGetCompositionString(IntPtr context, uint index, byte[] buffer, int length);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);

    IntPtr BackgroundBrush()
    {
        var origin = BackgroundPainter != null ? Parent.PointToClient(PointToScreen(Point.Empty)) : Launcher.PointToClient(PointToScreen(Point.Empty));
        int revision = BackgroundPainter != null ? BackgroundVersion : Launcher.Appearance.BackgroundRevision;
        if (backgroundBrush != IntPtr.Zero && backgroundRevision == revision && backgroundOrigin == origin && backgroundSize == ClientSize) return backgroundBrush;
        ReleaseBrush();
        using (var image = new Bitmap(Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height)))
        {
            using (var graphics = Graphics.FromImage(image))
            {
                if (BackgroundPainter != null) BackgroundPainter(graphics, new Rectangle(Point.Empty, image.Size), origin);
                else Launcher.Appearance.Paint(graphics, new Rectangle(Point.Empty, image.Size), origin);
            }
            backgroundBitmap = image.GetHbitmap(); backgroundBrush = CreatePatternBrush(backgroundBitmap);
        }
        backgroundRevision = revision; backgroundOrigin = origin; backgroundSize = ClientSize;
        return backgroundBrush;
    }

    void ReleaseBrush()
    {
        if (backgroundBrush != IntPtr.Zero) { DeleteObject(backgroundBrush); backgroundBrush = IntPtr.Zero; }
        if (backgroundBitmap != IntPtr.Zero) { DeleteObject(backgroundBitmap); backgroundBitmap = IntPtr.Zero; }
    }
    public void ReleaseBackground() { ReleaseBrush(); }

    void SetCompositionPreview(string text, int caret)
    {
        CompositionText = text ?? "";
        CompositionCaret = Math.Max(0, Math.Min(CompositionText.Length, caret));
        if (CompositionChanged != null) CompositionChanged(this, EventArgs.Empty);
    }

    void EndCandidateComposition()
    {
        if (!candidateComposition) return;
        candidateComposition = false; compositionKeyDown = Keys.None;
        Composing = false; SetCompositionPreview("", 0);
    }

    void UpdateCandidateComposition(Keys key)
    {
        if (!candidateComposition || (ModifierKeys & (Keys.Control | Keys.Alt)) != 0) return;
        string text = CompositionText ?? "";
        int caret = CompositionCaret;
        bool letter = key >= Keys.A && key <= Keys.Z;
        if (letter || key == Keys.OemQuotes)
        {
            int available = MaxLength - (TextLength - compositionSelection) - text.Length;
            if (MaxLength > 0 && available <= 0) return;
            string value = letter ? ((char)('a' + (int)key - (int)Keys.A)).ToString() : "'";
            text = text.Insert(caret, value); caret++;
        }
        else if (key == Keys.Back && caret > 0) text = text.Remove(--caret, 1);
        else if (key == Keys.Delete && caret < text.Length) text = text.Remove(caret, 1);
        else if (key == Keys.Left) caret = Math.Max(0, caret - 1);
        else if (key == Keys.Right) caret = Math.Min(text.Length, caret + 1);
        else if (key == Keys.Home) caret = 0;
        else if (key == Keys.End) caret = text.Length;
        else if (key == Keys.Escape) { EndCandidateComposition(); return; }
        else return;
        SetCompositionPreview(text, caret);
    }

    protected override void OnTextChanged(EventArgs e)
    {
        EndCandidateComposition();
        base.OnTextChanged(e);
    }

    protected override void OnLostFocus(EventArgs e)
    {
        EndCandidateComposition();
        base.OnLostFocus(e);
    }

    internal IntPtr PaintBackground(IntPtr dc)
    {
        if (BackgroundPainter == null && (Launcher == null || Launcher.Appearance == null || !Launcher.Appearance.IsCyber || Launcher.Appearance.IsRadial)) { ReleaseBrush(); return IntPtr.Zero; }
        IntPtr brush = BackgroundBrush();
        if (brush != IntPtr.Zero)
        {
            SetTextColor(dc, ColorTranslator.ToWin32(ForeColor));
            SetBkMode(dc, 1); SetBrushOrgEx(dc, 0, 0, IntPtr.Zero);
        }
        return brush;
    }

    protected override void WndProc(ref Message message)
    {
        // Some IMEs keep the reading string in their candidate window and send
        // candidate notifications without WM_IME_COMPOSITION or an IMM string.
        bool candidate = message.Msg == 0x0282 && (message.WParam.ToInt64() == 3 || message.WParam.ToInt64() == 5);
        if (candidate && !ReadOnly && !Composing)
        {
            Composing = true; candidateComposition = true;
            CompositionStart = SelectionStart; compositionSelection = SelectionLength;
            SetCompositionPreview("", 0);
        }
        Keys previewKey = Keys.None;
        if (candidateComposition && message.Msg == 0x0100)
        {
            int key = message.WParam.ToInt32();
            // A processed key retains its hardware scan code on physical input.
            if (key == 229) key = (int)MapVirtualKey((uint)((message.LParam.ToInt64() >> 16) & 255), 1);
            previewKey = (Keys)key; compositionKeyDown = previewKey;
        }
        if (candidateComposition && message.Msg == 0x0101)
        {
            Keys key = (Keys)message.WParam.ToInt32();
            if (key != compositionKeyDown) previewKey = key;
            compositionKeyDown = Keys.None;
        }
        bool composition = message.Msg == 0x010F;
        bool result = composition && (message.LParam.ToInt64() & 0x0800) != 0;
        bool preedit = composition && (!result || (message.LParam.ToInt64() & (0x0008 | 0x0080)) != 0);
        string preview = ""; int previewCaret = 0;
        if (message.Msg == 0x010D)
        {
            candidateComposition = false; compositionKeyDown = Keys.None;
            Composing = true; CompositionStart = SelectionStart; compositionSelection = SelectionLength; CompositionText = ""; CompositionCaret = 0;
            if (CompositionChanged != null) CompositionChanged(this, EventArgs.Empty);
        }
        if (composition)
        {
            candidateComposition = false; compositionKeyDown = Keys.None;
            if (!Composing) { Composing = true; CompositionStart = SelectionStart; compositionSelection = SelectionLength; }
            // A result string is inserted by the native editor below. Stop
            // overlaying its old preedit before TextChanged reports that commit.
            if (result) { CompositionText = ""; CompositionCaret = 0; }
            if (preedit)
            {
                IntPtr context = ImmGetContext(Handle);
                try
                {
                    int length = context == IntPtr.Zero ? 0 : ImmGetCompositionString(context, 8, null, 0);
                    if (length > 0 && length <= 32768)
                    {
                        var bytes = new byte[length]; ImmGetCompositionString(context, 8, bytes, bytes.Length);
                        preview = System.Text.Encoding.Unicode.GetString(bytes);
                        previewCaret = ImmGetCompositionString(context, 128, null, 0);
                    }
                }
                finally { if (context != IntPtr.Zero) ImmReleaseContext(Handle, context); }
            }
        }
        base.WndProc(ref message);
        if (previewKey != Keys.None) UpdateCandidateComposition(previewKey);
        if (message.Msg == 0x0282 && message.WParam.ToInt64() == 4) EndCandidateComposition();
        if (message.Msg == 0x0051) EndCandidateComposition();
        if (composition)
        {
            if (result) { CompositionStart = SelectionStart; compositionSelection = SelectionLength; }
            // Notify only after native editing and IMM context release; a
            // partial commit can then search its committed prefix + new preedit.
            SetCompositionPreview(preview, previewCaret);
        }
        if (message.Msg == 0x010E)
        {
            candidateComposition = false; compositionKeyDown = Keys.None;
            Composing = false; CompositionText = ""; CompositionCaret = 0;
            if (CompositionChanged != null) CompositionChanged(this, EventArgs.Empty);
        }
    }
    protected override void OnHandleDestroyed(EventArgs e) { ReleaseBrush(); base.OnHandleDestroyed(e); }
    protected override void Dispose(bool disposing) { if (disposing) ReleaseBrush(); base.Dispose(disposing); }
}

sealed class TokcatLauncherPlaceholder : Label
{
    protected override void OnPaint(PaintEventArgs e)
    {
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, ForeColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
    }
}
