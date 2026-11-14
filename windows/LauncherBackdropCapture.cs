using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

// A bounded producer samples only the desktop's overall color. The moving
// wheel never carries a detailed screen image or waits for screen capture.
public sealed class TokcatRadialBackdropCapture : IDisposable
{
    public sealed class Request
    {
        public Rectangle Bounds, VirtualScreen;
        public Color Fallback;
        public IntPtr[] Exclusions;
        public int Session;
    }
    public sealed class Frame : IDisposable
    {
        public readonly Color Color;
        public readonly Rectangle Bounds;
        public readonly long CapturedAt;
        public Frame(Color color, Rectangle bounds) { Color = color; Bounds = bounds; CapturedAt = Stopwatch.GetTimestamp(); }
        public double Luminance { get { return 0.2126 * Linear(Color.R) + 0.7152 * Linear(Color.G) + 0.0722 * Linear(Color.B); } }
        static double Linear(byte channel) { double value = channel / 255.0; return value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4); }
        public void Dispose() { }
    }
    readonly object gate = new object();
    readonly AutoResetEvent available = new AutoResetEvent(false);
    readonly Func<Request, Frame> capture;
    Thread worker;
    Request pending;
    Frame completed;
    int session;
    bool active, disposed;
    long requestedAt;
    public string LastError { get; private set; }
    public TokcatRadialBackdropCapture() : this(CaptureDesktop) { }
    public TokcatRadialBackdropCapture(Func<Request, Frame> capture) { this.capture = capture; }
    public void Begin()
    {
        lock (gate)
        {
            if (disposed) return;
            session++; active = true; requestedAt = 0; LastError = null;
            pending = null; if (completed != null) { completed.Dispose(); completed = null; }
            if (worker == null) { worker = new Thread(Run) { IsBackground = true, Name = "tokcat desktop blur" }; worker.Start(); }
        }
    }
    public void Enqueue(Rectangle bounds, Rectangle virtualScreen, Color fallback, IntPtr[] exclusions, bool force)
    {
        lock (gate)
        {
            if (!active || disposed) return;
            long now = Stopwatch.GetTimestamp();
            if (!force && requestedAt != 0 && now - requestedAt < Stopwatch.Frequency * 0.120) return;
            requestedAt = now;
            pending = new Request { Bounds = bounds, VirtualScreen = virtualScreen, Fallback = fallback, Exclusions = exclusions, Session = session };
            available.Set();
        }
    }
    public Frame TakeLatest()
    {
        lock (gate) { var result = completed; completed = null; return result; }
    }
    void Run()
    {
        try
        {
            while (true)
            {
                available.WaitOne();
                Request request;
                lock (gate) { if (disposed) return; request = pending; pending = null; }
                if (request == null) continue;
                Frame frame = null;
                try { frame = capture(request); }
                catch (Exception error)
                {
                    if (!(error is System.ComponentModel.Win32Exception) && !(error is ExternalException) && !(error is ArgumentException)) throw;
                    lock (gate) LastError = error.Message;
                }
                lock (gate)
                {
                    if (frame != null && active && !disposed && request.Session == session)
                    { if (completed != null) completed.Dispose(); completed = frame; frame = null; }
                    if (pending != null) available.Set();
                }
                if (frame != null) frame.Dispose();
            }
        }
        finally { available.Dispose(); }
    }
    [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr handle, uint affinity);
    [DllImport("dwmapi.dll")] static extern int DwmFlush();
    public static Color Average(Bitmap image)
    {
        int red = 0, green = 0, blue = 0, samples = 0, width = image.Width, height = image.Height;
        int stepX = Math.Max(1, width / 40), stepY = Math.Max(1, height / 8);
        for (int y = 0; y < height; y += stepY) for (int x = 0; x < width; x += stepX)
        { Color color = image.GetPixel(x, y); red += color.R; green += color.G; blue += color.B; samples++; }
        return Color.FromArgb(red / samples, green / samples, blue / samples);
    }
    static Frame CaptureDesktop(Request request)
    {
        var handles = request.Exclusions ?? new IntPtr[0];
        try
        {
            foreach (var handle in handles)
                if (!SetWindowDisplayAffinity(handle, 0x11)) throw new System.ComponentModel.Win32Exception();
            if (handles.Length > 0) DwmFlush();
            // Five small patches cover the center and four sides. Only their
            // average RGB survives; there is no large desktop bitmap to move,
            // blur, resample, or upload to the layered window on each mouse move.
            const int patch = 32;
            using (var source = new Bitmap(patch * 5, patch, PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(source))
                {
                    g.Clear(request.Fallback);
                    int cx = request.Bounds.Left + request.Bounds.Width / 2, cy = request.Bounds.Top + request.Bounds.Height / 2;
                    var points = new[] { new Point(cx, cy), new Point(cx - request.Bounds.Width / 4, cy), new Point(cx + request.Bounds.Width / 4, cy),
                        new Point(cx, cy - request.Bounds.Height / 4), new Point(cx, cy + request.Bounds.Height / 4) };
                    for (int i = 0; i < points.Length; i++)
                    {
                        var rectangle = new Rectangle(points[i].X - patch / 2, points[i].Y - patch / 2, patch, patch);
                        var visible = Rectangle.Intersect(rectangle, request.VirtualScreen);
                        if (!visible.IsEmpty) g.CopyFromScreen(visible.Location, new Point(i * patch + visible.X - rectangle.X, visible.Y - rectangle.Y), visible.Size);
                    }
                }
                foreach (var handle in handles) SetWindowDisplayAffinity(handle, 0);
                return new Frame(Average(source), request.Bounds);
            }
        }
        finally { foreach (var handle in handles) SetWindowDisplayAffinity(handle, 0); }
    }
    public void Stop()
    {
        lock (gate) { active = false; session++; pending = null; if (completed != null) { completed.Dispose(); completed = null; } }
    }
    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            active = false; disposed = true; session++; pending = null;
            if (completed != null) { completed.Dispose(); completed = null; }
            if (worker != null) available.Set(); else available.Dispose();
        }
    }
}
