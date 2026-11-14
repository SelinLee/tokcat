using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

// A separate message pump owns the visible wheel. Low-level mouse events only
// publish the newest position; neither dashboard callbacks nor WM_TIMER pacing
// can delay its translation. Bitmap production remains on the launcher thread.
public sealed class TokcatLauncherPointerFollower : IDisposable
{
    public sealed class HitRegion { public string Id; public double Radius, Angle, Span; }
    public sealed class ClickEvent : MouseEventArgs
    {
        public readonly string ItemId;
        public ClickEvent(MouseEventArgs source, string itemId) : base(source.Button, source.Clicks, source.X, source.Y, source.Delta) { ItemId = itemId; }
    }
    internal const int PresentMessage = 0x8001, MoveMessage = 0x8002, ConfigureMessage = 0x8003, HideMessage = 0x8004, CloseMessage = 0x8005;
    readonly object gate = new object();
    readonly ManualResetEventSlim ready = new ManualResetEventSlim(false);
    Thread thread;
    TokcatRadialSurface native;
    IntPtr handle;
    Bitmap pendingImage;
    HitRegion[] pendingRegions, displayedRegions = new HitRegion[0];
    float pendingScale = 1, displayedScale = 1;
    double pendingExtent, displayedExtent;
    Point pendingOrigin, pendingPointer;
    Rectangle bounds;
    Rectangle[] monitorBounds = new Rectangle[0], workingAreas = new Rectangle[0];
    volatile bool following = true, disposed;
    bool shownRequested;
    int moveQueued, presentQueued, generation, pendingGeneration;
    long pointerSentAt, lastMoveLatency;
    int nativeMoves;
    int nativePresents;
    long lastPresentTimestamp;
    readonly Queue<long> presentationTimes = new Queue<long>();
    Exception startupError;
    IntPtr dpiContext;
    internal readonly bool ReceiveNativeInput;
    public TokcatLauncherRadial Radial;
    public Action<Action> Dispatch;
    public event MouseEventHandler MouseDown;
    public IntPtr Handle { get { EnsureStarted(); return handle; } }
    public Rectangle Bounds { get { lock (gate) return bounds; } }
    public int NativeThreadId { get { return thread == null ? 0 : thread.ManagedThreadId; } }
    public int NativeMoveCount { get { return Volatile.Read(ref nativeMoves); } }
    public int NativePresentCount { get { return Volatile.Read(ref nativePresents); } }
    public long LastPresentTimestamp { get { return Interlocked.Read(ref lastPresentTimestamp); } }
    public long[] PresentationTimestamps { get { lock (gate) return presentationTimes.ToArray(); } }
    public double LastMoveLatencyMilliseconds { get { return Interlocked.Read(ref lastMoveLatency) * 1000.0 / Stopwatch.Frequency; } }
    public bool MouseHookActive { get; internal set; }
    public TokcatLauncherPointerFollower() : this(true) { }
    public TokcatLauncherPointerFollower(bool receiveNativeInput) { ReceiveNativeInput = receiveNativeInput; }
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, int message, IntPtr first, IntPtr second);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    void EnsureStarted()
    {
        lock (gate)
        {
            if (disposed) throw new ObjectDisposedException("TokcatLauncherPointerFollower");
            if (thread == null)
            {
                var screens = Screen.AllScreens;
                monitorBounds = screens.Select(s => s.Bounds).ToArray(); workingAreas = screens.Select(s => s.WorkingArea).ToArray();
                try { dpiContext = GetThreadDpiAwarenessContext(); } catch (EntryPointNotFoundException) { }
                thread = new Thread(Run) { IsBackground = true, Name = "tokcat pointer follower" };
                thread.SetApartmentState(ApartmentState.STA); thread.Start();
            }
        }
        if (!ready.Wait(5000)) throw new TimeoutException("The wheel presentation thread did not start.");
        if (startupError != null) throw new InvalidOperationException("Could not create the wheel surface.", startupError);
    }
    void Run()
    {
        try
        {
            if (dpiContext != IntPtr.Zero) try { SetThreadDpiAwarenessContext(dpiContext); } catch (EntryPointNotFoundException) { }
            native = new TokcatRadialSurface { Radial = Radial, Follower = this };
            native.MouseDown += delegate(object sender, MouseEventArgs e)
            {
                int version;
                lock (gate) { if (!shownRequested || disposed) return; version = generation; }
                // A click freezes the surface immediately, before its action is
                // dispatched to a possibly busy dashboard message pump.
                if (e.Button == MouseButtons.Left) { following = false; native.ConfigurePointer(false); }
                var callback = MouseDown; var dispatch = Dispatch;
                var click = new ClickEvent(e, HitTest(e.Location));
                if (callback != null && dispatch != null) dispatch(delegate { lock (gate) { if (!shownRequested || disposed || version != generation) return; } callback(this, click); });
            };
            handle = native.Handle; ready.Set();
            if (disposed) return;
            Application.Run();
        }
        catch (Exception error) { startupError = error; ready.Set(); }
        finally
        {
            if (native != null) native.Dispose();
            lock (gate) { if (pendingImage != null) { pendingImage.Dispose(); pendingImage = null; } handle = IntPtr.Zero; }
        }
    }
    public void SetFollowing(bool value)
    {
        if (!value) lock (gate) { if (!bounds.IsEmpty) pendingOrigin = bounds.Location; }
        following = value;
        IntPtr target = handle;
        if (target != IntPtr.Zero && !disposed) PostMessage(target, ConfigureMessage, IntPtr.Zero, IntPtr.Zero);
    }
    public void PublishPointer(Point point)
    {
        if (!following || disposed) return;
        lock (gate) { pendingPointer = point; pointerSentAt = Stopwatch.GetTimestamp(); }
        if (handle != IntPtr.Zero && Interlocked.Exchange(ref moveQueued, 1) == 0) PostMessage(handle, MoveMessage, IntPtr.Zero, IntPtr.Zero);
    }
    internal void MoveOnNativeThread()
    {
        Interlocked.Exchange(ref moveQueued, 0);
        Point pointer; Size size; long sent;
        lock (gate) { pointer = pendingPointer; size = bounds.Size; sent = pointerSentAt; }
        if (!following || !native.Visible || size.IsEmpty) return;
        Point origin = Place(pointer, size);
        native.MoveTo(origin);
        lock (gate) bounds = new Rectangle(origin, size);
        Interlocked.Increment(ref nativeMoves); Interlocked.Exchange(ref lastMoveLatency, Stopwatch.GetTimestamp() - sent);
    }
    Point Place(Point pointer, Size size)
    {
        Rectangle area = workingAreas.Length == 0 ? SystemInformation.VirtualScreen : workingAreas[0];
        for (int i = 0; i < monitorBounds.Length; i++) if (monitorBounds[i].Contains(pointer)) { area = workingAreas[i]; break; }
        int x = pointer.X - size.Width / 2, y = pointer.Y - size.Height / 2;
        return new Point(Math.Max(area.Left, Math.Min(x, area.Right - size.Width)), Math.Max(area.Top, Math.Min(y, area.Bottom - size.Height)));
    }
    public Point PointToScreen(Point point) { Rectangle current = Bounds; return new Point(current.X + point.X, current.Y + point.Y); }
    public void MoveTo(Point point)
    {
        // UI-side editor synchronization must never pull the visible wheel back
        // to an older timer-sampled pointer location.
        if (following || disposed || handle == IntPtr.Zero) return;
        lock (gate) pendingOrigin = point;
        PostMessage(handle, ConfigureMessage, IntPtr.Zero, IntPtr.Zero);
    }
    public void Update(Bitmap image, Point point, IntPtr launcher)
    { Update(image, point, launcher, new HitRegion[0], 1, image.Width / 2.0); }
    public void Update(Bitmap image, Point point, IntPtr launcher, HitRegion[] regions, float scale, double extent)
    {
        EnsureStarted();
        var copy = (Bitmap)image.Clone();
        lock (gate)
        {
            if (disposed) { copy.Dispose(); return; }
            if (pendingImage != null) pendingImage.Dispose();
            pendingImage = copy; pendingOrigin = point; pendingGeneration = generation;
            shownRequested = true;
            pendingRegions = regions; pendingScale = scale; pendingExtent = extent;
        }
        if (Interlocked.Exchange(ref presentQueued, 1) == 0) PostMessage(handle, PresentMessage, IntPtr.Zero, IntPtr.Zero);
    }
    internal void PresentOnNativeThread()
    {
        Interlocked.Exchange(ref presentQueued, 0);
        Bitmap image; Point origin; int version; HitRegion[] regions; float scale; double extent;
        lock (gate) { image = pendingImage; pendingImage = null; origin = pendingOrigin; version = pendingGeneration; regions = pendingRegions; scale = pendingScale; extent = pendingExtent; }
        if (image == null) return;
        using (image)
        {
            lock (gate) if (disposed || version != generation) return;
            // GetCursorPos is read on this independent thread, never from a
            // dashboard timer that may be hundreds of milliseconds behind.
            if (following) origin = Place(Cursor.Position, image.Size);
            native.Update(image, origin, IntPtr.Zero);
            long presentedAt = Stopwatch.GetTimestamp();
            Interlocked.Exchange(ref lastPresentTimestamp, presentedAt); Interlocked.Increment(ref nativePresents);
            lock (gate) { presentationTimes.Enqueue(presentedAt); while (presentationTimes.Count > 256) presentationTimes.Dequeue(); }
            displayedRegions = regions; displayedScale = scale; displayedExtent = extent;
            lock (gate) bounds = new Rectangle(origin, image.Size);
            native.ConfigurePointer(following);
        }
    }
    string HitTest(Point point)
    {
        double x = point.X / displayedScale - displayedExtent, y = point.Y / displayedScale - displayedExtent;
        double radius = Math.Sqrt(x * x + y * y), angle = Math.Atan2(y, x);
        foreach (var region in displayedRegions)
            if (Math.Abs(radius - region.Radius) <= 17 && TokcatRadialLayout.Wrap(angle - region.Angle + region.Span / 2) <= region.Span) return region.Id;
        return null;
    }
    internal void ConfigureOnNativeThread()
    {
        native.ConfigurePointer(following);
        if (!following && native.Visible)
        {
            Point origin; lock (gate) origin = pendingOrigin;
            native.MoveTo(origin); lock (gate) bounds = new Rectangle(origin, bounds.Size);
        }
    }
    public void Hide()
    {
        lock (gate)
        {
            generation++; shownRequested = false; bounds = Rectangle.Empty;
            if (pendingImage != null) { pendingImage.Dispose(); pendingImage = null; }
        }
        if (handle != IntPtr.Zero) PostMessage(handle, HideMessage, IntPtr.Zero, IntPtr.Zero);
    }
    internal void HideOnNativeThread() { native.ConfigurePointer(false); native.Hide(); }
    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return; disposed = true; generation++;
            if (pendingImage != null) { pendingImage.Dispose(); pendingImage = null; }
        }
        if (handle != IntPtr.Zero) PostMessage(handle, CloseMessage, IntPtr.Zero, IntPtr.Zero);
        else if (thread == null) ready.Dispose();
    }
}
