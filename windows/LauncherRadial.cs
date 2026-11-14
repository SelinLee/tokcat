using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// Port of macOS LauncherRadialLayout / Motion / ArcText. All geometry is in
// logical pixels, positive Y down. Painting and picking share presentation poses.
public sealed class TokcatRadialLayout
{
    public const int MaxRings = 3, MaxVisibleResults = 9;
    public const double InputRadius = 76, Thickness = 34, RingSpacing = 56, Feather = 20;
    public sealed class Slot
    {
        public int Index, Ring;
        public double Radius, Angle, Span;
        public PointF Center { get { return new PointF((float)(Math.Cos(Angle) * Radius), (float)(Math.Sin(Angle) * Radius)); } }
    }
    public readonly Slot[] Slots;
    public readonly int RingCount;
    public double OuterRadius { get { return 93 + (RingCount - 1) * RingSpacing; } }
    public double Diameter { get { return (OuterRadius + Feather) * 2; } }
    public TokcatRadialLayout(double[] weights)
    {
        var values = weights.Select(w => double.IsNaN(w) || double.IsInfinity(w) ? 1 : Math.Min(8, Math.Max(0.1, w))).ToArray();
        var ranked = Enumerable.Range(0, weights.Length).OrderByDescending(i => values[i]).ThenBy(i => i).Take(MaxVisibleResults).ToArray();
        var slots = new List<Slot>();
        if (ranked.Length > 0) slots.Add(new Slot { Index = ranked[0], Ring = 0, Radius = 76, Angle = Math.PI / 2, Span = Math.PI });
        int offset = Math.Min(1, ranked.Length), ring = 1;
        while (offset < ranked.Length && ring < MaxRings)
        {
            int capacity = 1 + ring * 2;
            var indices = ranked.Skip(offset).Take(capacity).ToArray();
            double step = Math.PI * 2 / indices.Length, maximum = Math.PI * 2 / capacity * 0.9;
            for (int p = 0; p < indices.Length; p++)
                slots.Add(new Slot { Index = indices[p], Ring = ring, Radius = 76 + ring * 56,
                    Angle = ((ring % 2 == 0 ? Math.PI / 2 : Math.PI * 1.5) + p * step) % (Math.PI * 2),
                    Span = Math.Max(Math.Min(0.42, maximum), maximum * Math.Sqrt(values[indices[p]] / values[ranked[0]])) });
            offset += indices.Length; ring++;
        }
        Slots = slots.ToArray(); RingCount = (Slots.Length == 0 ? 0 : Slots.Last().Ring) + 1;
    }
    public static double Wrap(double a) { return (a % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2); }
    public int HitTest(PointF point, bool aiming)
    {
        double distance = Math.Sqrt(point.X * point.X + point.Y * point.Y);
        if (distance < (aiming ? 24 : 59)) return -1;
        int ring = (int)Math.Round((distance - 76) / 56, MidpointRounding.AwayFromZero);
        if (aiming) ring = Math.Min(RingCount - 1, Math.Max(0, ring));
        if (ring < 0 || ring >= RingCount || (!aiming && Math.Abs(distance - (76 + ring * 56)) > 17)) return -1;
        double angle = Math.Atan2(point.Y, point.X);
        var slot = Slots.FirstOrDefault(s => s.Ring == ring && Wrap(angle - s.Angle + s.Span / 2) <= s.Span + 0.0001);
        return slot == null ? -1 : slot.Index;
    }
    public int Neighbor(int index, Keys direction, IDictionary<int, PointF> positions)
    {
        var current = Slots.FirstOrDefault(s => s.Index == index);
        if (current == null) return Slots.Length == 0 ? -1 : Slots[0].Index;
        Func<Slot, PointF> point = s => positions.ContainsKey(s.Index) ? positions[s.Index] : s.Center;
        PointF origin = point(current);
        if (direction == Keys.Down && current.Ring == 0)
        {
            var lower = Slots.Where(s => s.Ring == 1 && point(s).Y > 0 && Math.Abs(point(s).Y - origin.Y) <= 17).OrderBy(s => point(s).X).ToArray();
            if (lower.Length > 1) return lower[0].Index;
        }
        double ax = direction == Keys.Left ? -1 : direction == Keys.Right ? 1 : 0;
        double ay = direction == Keys.Up ? -1 : direction == Keys.Down ? 1 : 0;
        var candidates = Slots.Where(s => s.Index != index).Select(s => new { Slot = s, P = point(s) })
            .Where(s => !(direction == Keys.Down && origin.Y > 0 && s.P.Y > 0 && s.Slot.Ring < current.Ring))
            .Select(s => new { s.Slot, s.P, Forward = (s.P.X - origin.X) * ax + (s.P.Y - origin.Y) * ay,
                Sideways = Math.Abs((s.P.X - origin.X) * ay - (s.P.Y - origin.Y) * ax) }).Where(s => s.Forward > 0.5).ToArray();
        var aligned = candidates.Where(s => s.Sideways <= s.Forward).ToArray();
        var next = (aligned.Length == 0 ? candidates : aligned).OrderBy(s => Math.Round((s.Forward + s.Sideways * 2) * 2) / 2)
            .ThenBy(s => direction == Keys.Down ? s.P.X : s.Slot.Index).FirstOrDefault();
        if (next != null) return next.Slot.Index;
        if (direction == Keys.Down)
        {
            var sibling = Slots.Where(s => s.Ring == current.Ring && Math.Abs(point(s).Y - origin.Y) < 8.5 && point(s).X > origin.X + 0.5).OrderBy(s => point(s).X).FirstOrDefault();
            if (sibling != null) return sibling.Index;
        }
        return index;
    }
}

public sealed class TokcatRadialMotion
{
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint parameter, out bool value, uint flags);
    public static bool ReducedMotion { get { bool enabled; return SystemParametersInfo(0x1042, 0, out enabled, 0) && !enabled; } }
    public sealed class Pose
    {
        public double Radius, Angle, Span, Opacity = 1, Compression;
        public Pose Copy() { return (Pose)MemberwiseClone(); }
        public PointF Center { get { return new PointF((float)(Math.Cos(Angle) * Radius), (float)(Math.Sin(Angle) * Radius)); } }
    }
    public sealed class Entry
    {
        public TokcatLauncherResult Item;
        public int Ring;
        public Pose Pose;
        public bool Departing;
        public string Id { get { return Item.Key; } }
    }
    public sealed class Band { public string Id; public int Ring; public Pose Pose; }
    public sealed class Bridge { public int Ring; public double Radius, Start, End, Opacity; }
    public Entry[] Entries = new Entry[0];
    public Band[] Bands = new Band[0];
    public Bridge[] Bridges = new Bridge[0];
    public double Extent = 113, Flow, Phase;
    public bool IsAnimating { get; private set; }
    Entry[] source = new Entry[0], destination = new Entry[0];
    Band[] sourceBands = new Band[0], destinationBands = new Band[0];
    double targetExtent = 113, sourceFlow, sourcePhase;
    readonly Stopwatch clock = new Stopwatch();
    public void Update(TokcatLauncherResult[] items, TokcatRadialLayout layout, bool animated)
    {
        var next = layout.Slots.Select(s => new Entry { Item = items[s.Index], Ring = s.Ring, Pose = new Pose { Radius = s.Radius, Angle = s.Angle, Span = s.Span } }).ToArray();
        bool same = next.Length == destination.Length && next.Zip(destination, (a, b) => a.Id == b.Id && a.Pose.Radius == b.Pose.Radius && a.Pose.Angle == b.Pose.Angle && a.Pose.Span == b.Pose.Span).All(v => v);
        destination = next;
        destinationBands = layout.Slots.GroupBy(s => s.Ring).Select(g => new Band { Ring = g.Key, Id = g.Key + (g.Count() > 1 ? ":circle" : ":arc"),
            Pose = new Pose { Radius = 76 + g.Key * 56, Angle = g.Count() > 1 ? Math.PI : g.First().Angle, Span = g.Count() > 1 ? Math.PI * 2 : g.First().Span } }).ToArray();
        targetExtent = layout.Diameter / 2;
        if (same)
        {
            foreach (var entry in Entries.Concat(source)) { var item = next.FirstOrDefault(e => e.Id == entry.Id); if (item != null) entry.Item = item.Item; }
            if ((!animated || ReducedMotion) && IsAnimating) Finish();
            return;
        }
        if (!animated || ReducedMotion) { Finish(); return; }
        source = next.Select(e => {
            var old = Entries.FirstOrDefault(p => p.Id == e.Id);
            var pose = old == null ? e.Pose.Copy() : old.Pose.Copy();
            // Keep the positional spring, but make a fresh match legible and
            // available to hit testing on its first presented frame.
            if (old == null) { pose.Radius -= 12; pose.Span *= 0.85; pose.Opacity = 0.85; }
            else if (old.Departing) pose.Opacity = Math.Max(0.85, pose.Opacity);
            return new Entry { Item = e.Item, Ring = e.Ring, Pose = pose };
        }).Concat(Entries.Where(e => e.Pose.Opacity > 0.02 && !next.Any(n => n.Id == e.Id))
            .OrderByDescending(e => e.Pose.Opacity).Take(TokcatRadialLayout.MaxVisibleResults)
            .Select(e => new Entry { Item = e.Item, Ring = e.Ring, Pose = e.Pose.Copy(), Departing = true })).ToArray();
        sourceBands = destinationBands.Select(b => {
            var old = Bands.FirstOrDefault(p => p.Id == b.Id); var pose = old == null ? b.Pose.Copy() : old.Pose.Copy();
            if (old == null) { pose.Radius -= 12; pose.Opacity = 0.85; }
            return new Band { Id = b.Id, Ring = b.Ring, Pose = pose };
        }).Concat(Bands.Where(b => b.Pose.Opacity > 0.02 && !destinationBands.Any(n => n.Id == b.Id))
            .OrderByDescending(b => b.Pose.Opacity).Take(TokcatRadialLayout.MaxRings)).ToArray();
        Extent = Math.Max(Extent, targetExtent); sourceFlow = Flow; sourcePhase = Phase;
        Entries = source; Bands = sourceBands; IsAnimating = true; clock.Restart();
    }
    public void Finish() { Entries = destination; Bands = destinationBands; Bridges = new Bridge[0]; Extent = targetExtent; Flow = Phase = 0; IsAnimating = false; clock.Stop(); }
    static Pose Retiring(Pose p) { var r = p.Copy(); r.Radius -= 19; if (r.Span < Math.PI * 1.99) r.Span *= 0.8; r.Opacity = 0; return r; }
    public void Advance(double elapsed)
    {
        if (!IsAnimating) return;
        double t = elapsed < 0 ? clock.Elapsed.TotalSeconds : elapsed;
        if (t >= 0.96) { Finish(); return; }
        double spring = 1 - Math.Exp(-7.5 * t) * (Math.Cos(11 * t) + 7.5 / 11 * Math.Sin(11 * t));
        double fade = Math.Min(1, t / 0.46), alpha = fade * fade * (3 - 2 * fade);
        double visibility = Math.Min(1, t / 0.11);
        visibility *= 2 - visibility;
        Flow = Math.Min(1.35, sourceFlow * (1 - alpha) + Math.Pow(Math.Max(0, Math.Sin(Math.PI * t / 0.96)), 0.75));
        Phase = sourcePhase + t * 8;
        Func<Pose, Pose, Pose> interpolate = (a, b) => new Pose { Radius = Math.Max(24, a.Radius + (b.Radius - a.Radius) * spring),
            Angle = a.Angle + Math.Atan2(Math.Sin(b.Angle - a.Angle), Math.Cos(b.Angle - a.Angle)) * spring,
            Span = Math.Min(Math.PI * 2, Math.Max(0.08, a.Span + (b.Span - a.Span) * spring)), Opacity = a.Opacity + (b.Opacity - a.Opacity) * visibility, Compression = a.Compression * (1 - alpha) };
        Entries = source.Select(e => { var target = destination.FirstOrDefault(d => d.Id == e.Id); return new Entry { Item = e.Item, Ring = e.Ring, Departing = e.Departing, Pose = interpolate(e.Pose, target == null ? Retiring(e.Pose) : target.Pose) }; }).ToArray();
        Bands = sourceBands.Select(b => { var target = destinationBands.FirstOrDefault(d => d.Id == b.Id); return new Band { Id = b.Id, Ring = b.Ring, Pose = interpolate(b.Pose, target == null ? Retiring(b.Pose) : target.Pose) }; }).ToArray();
        var offsets = new double[Entries.Length]; var contacts = new double[Entries.Length]; var bridges = new List<Bridge>();
        for (int i = 0; i < Entries.Length; i++) for (int j = i + 1; j < Entries.Length; j++)
        {
            var a = Entries[i]; var b = Entries[j];
            if (a.Ring != b.Ring || Math.Abs(a.Pose.Radius - b.Pose.Radius) >= 2 || Math.Min(a.Pose.Opacity, b.Pose.Opacity) <= 0.03) continue;
            double delta = Math.Atan2(Math.Sin(b.Pose.Angle - a.Pose.Angle), Math.Cos(b.Pose.Angle - a.Pose.Angle));
            double direction = delta >= 0 ? 1 : -1, separation = Math.Abs(delta);
            if (separation <= 0.01) continue;
            bool between = Entries.Where((e, k) => k != i && k != j && e.Ring == a.Ring && Math.Abs(e.Pose.Radius - a.Pose.Radius) < 2 && e.Pose.Opacity > 0.03)
                .Any(e => { double relative = TokcatRadialLayout.Wrap((e.Pose.Angle - a.Pose.Angle) * direction); return relative > 0.01 && relative < separation - 0.01; });
            if (between) continue;
            double radius = (a.Pose.Radius + b.Pose.Radius) / 2, gap = separation - (a.Pose.Span + b.Pose.Span) / 2;
            if (gap >= 1.05 || gap * radius >= 130) continue;
            double contact = Math.Min(1, Math.Max(0, 1 - gap * radius / 130)) * Math.Min(1, Flow);
            contacts[i] = Math.Max(contacts[i], contact); contacts[j] = Math.Max(contacts[j], contact);
            double push = Math.Max(0, 0.12 - gap) * 0.16 * Flow, pull = contact * 0.055 * Math.Sin(Math.Min(1, t / 0.52) * Math.PI);
            offsets[i] -= direction * (push - pull); offsets[j] += direction * (push - pull);
            double middle = (a.Pose.Angle + direction * a.Pose.Span / 2 + a.Pose.Angle + delta - direction * b.Pose.Span / 2) / 2;
            double span = Math.Max(0.08, Math.Abs(gap) + 0.08);
            bridges.Add(new Bridge { Ring = a.Ring, Radius = radius, Start = middle - span / 2, End = middle + span / 2,
                Opacity = Math.Min(a.Pose.Opacity, b.Pose.Opacity) * Math.Min(1, Flow) * Math.Pow(contact, 0.35) });
        }
        for (int i = 0; i < Entries.Length; i++) { Entries[i].Pose.Angle += Math.Min(0.09, Math.Max(-0.09, offsets[i])) * alpha; Entries[i].Pose.Compression += contacts[i] * alpha; }
        Bridges = bridges.ToArray();
    }
    public string HitTest(PointF point)
    {
        double distance = Math.Sqrt(point.X * point.X + point.Y * point.Y), angle = Math.Atan2(point.Y, point.X);
        var entry = Entries.Where(e => !e.Departing && e.Pose.Opacity > 0.25 && Math.Abs(distance - e.Pose.Radius) <= 17 &&
            TokcatRadialLayout.Wrap(angle - e.Pose.Angle + e.Pose.Span * (1 - e.Pose.Compression * 0.12) / 2) <= e.Pose.Span * (1 - e.Pose.Compression * 0.12))
            .OrderBy(e => Math.Pow(point.X - e.Pose.Center.X, 2) + Math.Pow(point.Y - e.Pose.Center.Y, 2)).FirstOrDefault();
        return entry == null ? null : entry.Id;
    }
}

public sealed class TokcatLauncherRadial : IDisposable, IMessageFilter
{
    readonly TokcatLauncherWindow window;
    readonly TokcatLauncherIcons icons;
    readonly TokcatLauncherPointerFollower surface = new TokcatLauncherPointerFollower();
    readonly System.Threading.Timer timer;
    const int FrameMessage = 0x8006;
    IntPtr frameWindow;
    int tickQueued, frameRequested;
    bool disposed;
    public readonly TokcatRadialMotion Motion = new TokcatRadialMotion();
    public TokcatRadialLayout Layout { get; private set; }
    bool following;
    public bool Following
    {
        get { return following; }
        private set
        {
            following = value; surface.SetFollowing(value);
            if (!value && window != null && !surface.Bounds.IsEmpty) window.Location = surface.Bounds.Location;
        }
    }
    public bool Aiming { get; private set; }
    public bool Reading { get; private set; }
    public int AimIndex { get; private set; }
    public PointF AimVector { get; private set; }
    public float Scale { get; private set; }
    public bool PointerLocked { get; private set; }
    public event EventHandler FrameChanged;
    bool filtering, ignoreControl, wasFollowing, rendering, preciseTimer;
    volatile bool dirty = true;
    int iconRevision, renderedIconRevision;
    public double LastRenderMilliseconds { get; private set; }
    Bitmap contentLayer, presentation;
    byte[] maskPixels, animatedMaskPixels, maskRasterPixels;
    int[] framePixels;
    readonly int[] fogPalette = new int[256];
    int fogColor;
    string contentKey;
    string maskKey;
    readonly Dictionary<string, byte[]> maskCache = new Dictionary<string, byte[]>();
    sealed class ResultSprite : IDisposable
    {
        public Bitmap Icon;
        public GraphicsPath Text;
        public Color TextColor;
        public int Size, IconRevision;
        public void Dispose() { Icon.Dispose(); Text.Dispose(); }
    }
    readonly Dictionary<string, TokcatRadialMotion.Pose> resultGeometry = new Dictionary<string, TokcatRadialMotion.Pose>();
    readonly Dictionary<string, ResultSprite> resultSprites = new Dictionary<string, ResultSprite>();
    readonly Queue<string> spriteOrder = new Queue<string>();
    sealed class LabelGlyph
    {
        public GraphicsPath Outline;
        public double Advance;
    }
    readonly Dictionary<string, LabelGlyph> labelGlyphs = new Dictionary<string, LabelGlyph>();
    public int SpriteBuildCount { get; private set; }
    public int CachedSpriteCount { get { return resultSprites.Count; } }
    public int MaskBuildCount { get; private set; }
    public int ContentBuildCount { get; private set; }
    bool lostActivation;
    Point previousPointer, lockedPointer;
    NativeRect previousClip;
    int selectionStart = -1, selectionLength = -1;
    readonly TokcatRadialReadingWindow dictionaryWindow = new TokcatRadialReadingWindow();
    readonly TokcatLauncherTextBox readingText = new TokcatLauncherTextBox { Multiline = true, ReadOnly = true, BorderStyle = BorderStyle.None, ScrollBars = ScrollBars.Vertical, Font = new Font("Microsoft YaHei UI", 9.75f) };
    public static readonly Color TransparentKey = Color.FromArgb(1, 2, 3);
    public TokcatLauncherResult[] Items { get { return window.Results.Items.Cast<TokcatLauncherResult>().ToArray(); } }
    volatile TokcatLauncherResult[] accessibleItems = new TokcatLauncherResult[0];
    volatile int accessibleSelected = -1;
    public TokcatLauncherResult[] AccessibleItems { get { return accessibleItems; } }
    public bool Active { get { return window.Appearance != null && window.Appearance.IsRadial; } }
    [DllImport("user32.dll")] static extern bool HideCaret(IntPtr handle);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr handle, int message, IntPtr first, IntPtr second);
    [DllImport("user32.dll")] static extern uint GetQueueStatus(uint flags);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint period);
    [StructLayout(LayoutKind.Sequential)] struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct RawDevice { public ushort Page, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] struct RawHeader { public uint Type, Size; public IntPtr Device, Parameter; }
    [DllImport("user32.dll")] static extern bool GetClipCursor(out NativeRect rectangle);
    [DllImport("user32.dll")] static extern bool ClipCursor(ref NativeRect rectangle);
    [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr handle, uint affinity);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr handle, uint flags);
    [DllImport("user32.dll")] static extern bool RegisterRawInputDevices(RawDevice[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr input, uint command, [Out] byte[] data, ref uint size, uint headerSize);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr handle, int message, IntPtr wparam, IntPtr lparam);
    public TokcatLauncherRadial(TokcatLauncherWindow window, TokcatLauncherIcons icons)
    {
        this.window = window; this.icons = icons; Scale = 1; Layout = new TokcatRadialLayout(new double[0]);
        surface.Radial = this;
        surface.Dispatch = delegate(Action action)
        {
            try { if (window.IsHandleCreated && !window.IsDisposed) window.BeginInvoke(action); }
            catch (InvalidOperationException) { }
        };
        Following = true; AimIndex = -1;
        surface.MouseDown += delegate(object sender, MouseEventArgs e) {
            if (e.Button != MouseButtons.Left) return;
            if (!surface.Bounds.IsEmpty) window.Location = surface.Bounds.Location;
            if (Aiming) { FinishAim(true); return; }
            Following = false; window.Query.Focus();
            var snapshot = e as TokcatLauncherPointerFollower.ClickEvent;
            string id = snapshot == null ? Motion.HitTest(LocalPoint(surface.PointToScreen(e.Location))) : snapshot.ItemId;
            int index = Array.FindIndex(Items, r => r.Key == id);
            if (index >= 0) { window.Results.SelectedIndex = index; window.SubmitRadial(); }
        };
        timer = new System.Threading.Timer(delegate { QueueFrame(); }, null, System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite);
        window.VisibleChanged += delegate { if (!window.Visible) Stop(); };
        // The fog carries only an overall color, so moving a settled wheel is
        // a compositor translation, independent of sampling or rasterization.
        window.LocationChanged += delegate { if (Active && window.Visible && !window.IsPreview) surface.MoveTo(window.Location); };
        window.Results.SelectedIndexChanged += delegate { accessibleSelected = window.Results.SelectedIndex; dirty = true; };
        window.Query.TextChanged += delegate { dirty = true; };
        window.Query.CompositionChanged += delegate { CancelAim(); dirty = true; };
        icons.Changed += delegate { System.Threading.Interlocked.Increment(ref iconRevision); dirty = true; };
        dictionaryWindow.Initialize(readingText, window);
        dictionaryWindow.AccessibleName = "词典释义"; readingText.AccessibleName = "词典释义，可滚动阅读";
        dictionaryWindow.Deactivate += delegate { NotifyDeactivated(); };
        Application.ApplicationExit += OnExit;
    }
    void OnExit(object sender, EventArgs e) { UnlockPointer(); }
    public bool SetCaptureAffinity(uint affinity)
    {
        return SetWindowDisplayAffinity(surface.Handle, affinity) && dictionaryWindow.SetCaptureAffinity(affinity);
    }
    public IntPtr[] CaptureHandles { get { return new[] { window.Handle, surface.Handle }.Concat(dictionaryWindow.CaptureHandles).ToArray(); } }
    public bool OwnsFocus { get { return dictionaryWindow.ContainsFocus; } }
    public void NotifyDeactivated() { lostActivation = true; }
    public Rectangle DefinitionBounds { get { return dictionaryWindow.Visible ? Rectangle.Inflate(dictionaryWindow.Bounds, (int)(16 * window.LayoutScale), (int)(26 * window.LayoutScale)) : Rectangle.Empty; } }
    public int SelectedIndex { get { return accessibleSelected; } }
    public Point ScreenOrigin { get { var live = surface.Bounds; return live.IsEmpty ? window.Location : live.Location; } }
    public void PerformAccessibleItem(string id)
    {
        if (window.IsPreview || !window.Visible) return;
        Action perform = delegate { int index = Array.FindIndex(Items, r => r.Key == id); if (index >= 0) { window.Results.SelectedIndex = index; window.SubmitRadial(); } };
        if (window.InvokeRequired) window.BeginInvoke(perform); else perform();
    }
    public void Configure()
    {
        Stop(); Following = true; dirty = true;
        if (Active) Update(false);
    }
    public void Update(bool animated)
    {
        if (!Active) return;
        var current = Items; accessibleItems = current;
        Layout = new TokcatRadialLayout(current.Select(i => i.RadialWeight).ToArray());
        var retained = new HashSet<string>(current.Select(i => i.Key).Concat(Motion.Entries.Select(e => e.Id)));
        foreach (var id in resultGeometry.Keys.Where(id => !retained.Contains(id)).ToArray()) resultGeometry.Remove(id);
        foreach (var slot in Layout.Slots) resultGeometry[current[slot.Index].Key] = new TokcatRadialMotion.Pose { Radius = slot.Radius, Span = slot.Span };
        Motion.Update(current, Layout, animated && !Aiming && !window.IsPreview);
        ResizeCanvas(); dirty = true;
        if (window.Visible && !window.IsPreview) QueueFrame();
        if (window.IsPreview && FrameChanged != null) FrameChanged(this, EventArgs.Empty);
    }
    public void Present()
    {
        if (!Active || window.IsPreview) return;
        lostActivation = false;
        previousPointer = Cursor.Position; ignoreControl = (Control.ModifierKeys & Keys.Control) != 0;
        if (!filtering) { Application.AddMessageFilter(this); filtering = true; }
        surface.SetFollowing(Following);
        if (!preciseTimer) preciseTimer = timeBeginPeriod(1) == 0;
        System.Threading.Interlocked.Exchange(ref frameWindow, window.Handle);
        // Stay below the legacy ~15.6 ms timer tick. A native posted message
        // yields to queued keyboard input even when a frame takes too long.
        timer.Change(15, 15); dirty = true; Tick();
        ShowDictionary();
    }
    void QueueFrame()
    {
        IntPtr target = System.Threading.Interlocked.CompareExchange(ref frameWindow, IntPtr.Zero, IntPtr.Zero);
        if (disposed || target == IntPtr.Zero) return;
        System.Threading.Interlocked.Exchange(ref frameRequested, 1);
        if (System.Threading.Interlocked.Exchange(ref tickQueued, 1) != 0) return;
        if (!PostMessage(target, FrameMessage, IntPtr.Zero, IntPtr.Zero)) System.Threading.Interlocked.Exchange(ref tickQueued, 0);
    }
    public bool ProcessFrameMessage(ref Message message)
    {
        if (message.Msg != FrameMessage) return false;
        // A slow frame must not queue another animation frame ahead of the
        // keystrokes that arrive while its result labels are being painted.
        System.Threading.Interlocked.Exchange(ref frameRequested, 0);
        try { if (!disposed) Tick(); }
        finally
        {
            System.Threading.Interlocked.Exchange(ref tickQueued, 0);
            const uint qsKey = 1;
            if (System.Threading.Volatile.Read(ref frameRequested) != 0 && (GetQueueStatus(qsKey) >> 16) == 0) QueueFrame();
        }
        return true;
    }
    public void ResetAnchor()
    {
        Following = true; Motion.Finish(); ResizeCanvas(); Follow(Cursor.Position); previousPointer = Cursor.Position;
    }
    void ResizeCanvas()
    {
        var area = Screen.FromPoint(window.IsPreview ? window.Location : Cursor.Position).WorkingArea;
        float scale = Math.Min(window.LayoutScale, (float)(Math.Min(area.Width, area.Height) / (Motion.Extent * 2)));
        if (window.IsPreview) scale = window.LayoutScale;
        Point center = new Point(window.Left + window.Width / 2, window.Top + window.Height / 2);
        Scale = Math.Max(0.1f, scale);
        int side = (int)Math.Ceiling(Motion.Extent * 2 * Scale);
        if (window.ClientSize != new Size(side, side))
        {
            window.ClientSize = new Size(side, side);
            window.LayoutRadialEditor();
        }
        if (!window.IsPreview) Follow(Following ? Cursor.Position : center);
    }
    void Follow(Point point)
    {
        window.Location = TokcatLauncherWindow.Constrain(new Point(point.X - window.Width / 2, point.Y - window.Height / 2), window.Size);
    }
    PointF LocalPoint(Point point) { return new PointF((point.X - window.Left) / Scale - (float)Motion.Extent, (point.Y - window.Top) / Scale - (float)Motion.Extent); }
    public void Navigate(Keys direction)
    {
        CancelAim(); ignoreControl = true; Following = false;
        var positions = new Dictionary<int, PointF>(); var items = Items;
        foreach (var entry in Motion.Entries.Where(e => !e.Departing)) { int index = Array.FindIndex(items, r => r.Key == entry.Id); if (index >= 0) positions[index] = entry.Pose.Center; }
        int next = Layout.Neighbor(window.Results.SelectedIndex, direction, positions);
        if (next >= 0) window.Results.SelectedIndex = next;
        dirty = true;
    }
    public bool BeginAim()
    {
        if (!Active || window.Query.Composing || window.IsPreview || PointerLocked) return false;
        Motion.Finish(); ResizeCanvas(); wasFollowing = Following; Following = false;
        GetClipCursor(out previousClip); lockedPointer = Cursor.Position;
        // Raw mouse deltas keep the ray moving while the actual pointer remains
        // stationary, matching the Mac cursor association without warp jitter.
        var device = new RawDevice { Page = 1, Usage = 2, Flags = 0x100, Target = window.Handle };
        if (!RegisterRawInputDevices(new[] { device }, 1, (uint)Marshal.SizeOf(typeof(RawDevice)))) { Following = wasFollowing; return false; }
        var clip = new NativeRect { Left = lockedPointer.X, Top = lockedPointer.Y, Right = lockedPointer.X + 1, Bottom = lockedPointer.Y + 1 };
        if (!ClipCursor(ref clip))
        {
            RegisterRawInputDevices(new[] { new RawDevice { Page = 1, Usage = 2, Flags = 1 } }, 1, (uint)Marshal.SizeOf(typeof(RawDevice)));
            Following = wasFollowing; return false;
        }
        PointerLocked = true; Aiming = true; Reading = false; AimIndex = -1; AimVector = PointF.Empty;
        previousPointer = lockedPointer; dirty = true; return true;
    }
    public void MoveAim(float dx, float dy)
    {
        if (!Aiming || Reading) return;
        double x = AimVector.X + dx, y = AimVector.Y + dy, length = Math.Sqrt(x * x + y * y), limit = Layout.OuterRadius + 16;
        if (length > limit) { x *= limit / length; y *= limit / length; }
        AimVector = new PointF((float)x, (float)y); AimIndex = Layout.HitTest(AimVector, true);
        if (AimIndex >= 0) window.Results.SelectedIndex = AimIndex;
        dirty = true;
    }
    public void FinishAim(bool commit)
    {
        if (!Aiming) { UnlockPointer(); return; }
        int target = commit && !Reading ? AimIndex : -1;
        Aiming = false; Reading = false; AimIndex = -1; AimVector = PointF.Empty; Following = wasFollowing;
        UnlockPointer(); dirty = true;
        if (target >= 0 && target < Items.Length) { window.Results.SelectedIndex = target; window.SubmitRadial(); }
    }
    public void CancelAim() { FinishAim(false); }
    void UnlockPointer()
    {
        if (!PointerLocked) return;
        RegisterRawInputDevices(new[] { new RawDevice { Page = 1, Usage = 2, Flags = 1 } }, 1, (uint)Marshal.SizeOf(typeof(RawDevice)));
        ClipCursor(ref previousClip); PointerLocked = false;
    }
    public bool PreFilterMessage(ref Message message)
    {
        if (!Active || !window.Visible || window.IsPreview) return false;
        if (message.Msg == 0x00FF && Aiming)
        {
            uint size = 0, header = (uint)Marshal.SizeOf(typeof(RawHeader));
            if (GetRawInputData(message.LParam, 0x10000003, null, ref size, header) == 0 && size >= header + 24 && size <= 65536)
            {
                var bytes = new byte[size];
                if (GetRawInputData(message.LParam, 0x10000003, bytes, ref size, header) != uint.MaxValue && BitConverter.ToUInt32(bytes, 0) == 0 && (BitConverter.ToUInt16(bytes, (int)header) & 1) == 0)
                    MoveAim(BitConverter.ToInt32(bytes, (int)header + 12) * 1.6f / Scale, BitConverter.ToInt32(bytes, (int)header + 16) * 1.6f / Scale);
            }
            // Let DefWindowProc perform WM_INPUT cleanup.
            return false;
        }
        if (message.Msg == 0x0100 || message.Msg == 0x0104)
        {
            Keys key = (Keys)message.WParam.ToInt32();
            if (key == Keys.ControlKey || key == Keys.LControlKey || key == Keys.RControlKey) { if (!ignoreControl && (Control.ModifierKeys & (Keys.Shift | Keys.Alt)) == 0) BeginAim(); return false; }
            if (Aiming)
            {
                if (key == Keys.Enter)
                {
                    // Keep Windows' existing reveal-file shortcut when a Ctrl
                    // hold has not yet pointed at a sector.
                    var selected = window.Results.SelectedItem as TokcatLauncherResult;
                    if (selected != null && selected.Kind == "file" && AimVector.X * AimVector.X + AimVector.Y * AimVector.Y < 24 * 24) { CancelAim(); ignoreControl = true; return false; }
                    FinishAim(true); return true;
                }
                CancelAim(); ignoreControl = true;
            }
        }
        if ((message.Msg == 0x0101 || message.Msg == 0x0105) && ((Keys)message.WParam.ToInt32() == Keys.ControlKey || (Keys)message.WParam.ToInt32() == Keys.LControlKey || (Keys)message.WParam.ToInt32() == Keys.RControlKey))
        { FinishAim(true); ignoreControl = false; }
        if (message.Msg == 0x020A && Aiming && window.DictionaryDefinition != null)
        {
            Reading = true; AimIndex = -1; AimVector = PointF.Empty;
            int delta = (short)(message.WParam.ToInt64() >> 16);
            SendMessage(readingText.Handle, 0x00B6, IntPtr.Zero, new IntPtr(-delta / 40)); dirty = true; return true;
        }
        if (message.Msg == 0x0201 && Aiming) { FinishAim(true); return true; }
        return false;
    }
    void Tick()
    {
        if (!Active || !window.Visible || window.IsPreview) return;
        IntPtr foreground = GetForegroundWindow();
        bool ownForeground = foreground == window.Handle || foreground == surface.Handle || foreground == dictionaryWindow.Handle || GetAncestor(foreground, 3) == window.Handle;
        if (ownForeground) lostActivation = false;
        else if (lostActivation && foreground != IntPtr.Zero) { window.Hide(); return; }
        if (window.Query.Composing && Aiming) { CancelAim(); ignoreControl = true; }
        if ((Control.ModifierKeys & (Keys.Shift | Keys.Alt)) != 0 && Aiming) { CancelAim(); ignoreControl = true; }
        bool control = (Control.ModifierKeys & Keys.Control) != 0;
        if (!control && Aiming) { FinishAim(true); ignoreControl = false; }
        if (!control) ignoreControl = false;
        Point pointer = Cursor.Position;
        if (!Aiming && pointer != previousPointer)
        {
            if (Following)
            {
                // Only synchronize the hidden editor here. The visible wheel
                // follows mouse events on its own independent message pump.
                var live = surface.Bounds;
                if (live.IsEmpty) Follow(pointer); else window.Location = live.Location;
            }
            else if (!Aiming)
            {
                string id = Motion.HitTest(LocalPoint(pointer)); int index = Array.FindIndex(Items, r => r.Key == id);
                if (index >= 0) window.Results.SelectedIndex = index;
            }
            if (!Following) dirty = true;
        }
        previousPointer = pointer;
        if (Following && !surface.Bounds.IsEmpty) window.Location = surface.Bounds.Location;
        if (Motion.IsAnimating)
        {
            double extent = Motion.Extent; Motion.Advance(-1);
            if (extent != Motion.Extent) ResizeCanvas();
            dirty = true;
        }
        if (window.Appearance.PollRadialBackground()) dirty = true;
        if (selectionStart != window.Query.SelectionStart || selectionLength != window.Query.SelectionLength) { selectionStart = window.Query.SelectionStart; selectionLength = window.Query.SelectionLength; dirty = true; }
        HideCaret(window.Query.Handle);
        if (renderedIconRevision != System.Threading.Volatile.Read(ref iconRevision)) dirty = true;
        if (!dirty || rendering) return;
        rendering = true;
        try
        {
            long started = Stopwatch.GetTimestamp();
            int revision = System.Threading.Volatile.Read(ref iconRevision);
            Size size = new Size(Math.Max(1, window.Width), Math.Max(1, window.Height));
            if (presentation == null || presentation.Size != size) { if (presentation != null) presentation.Dispose(); presentation = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppPArgb); }
            RenderInto(presentation);
            var hitRegions = Motion.Entries.Where(e => !e.Departing && e.Pose.Opacity > 0.25).Select(e => new TokcatLauncherPointerFollower.HitRegion {
                Id = e.Id, Radius = e.Pose.Radius, Angle = e.Pose.Angle, Span = e.Pose.Span * (1 - e.Pose.Compression * 0.12) }).ToArray();
            surface.Update(presentation, window.Location, window.Handle, hitRegions, Scale, Motion.Extent);
            renderedIconRevision = revision; dirty = revision != System.Threading.Volatile.Read(ref iconRevision); ShowDictionary();
            LastRenderMilliseconds = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
        }
        finally { rendering = false; }
    }
    public void Invalidate() { dirty = true; }
    public void Stop()
    {
        System.Threading.Interlocked.Exchange(ref frameWindow, IntPtr.Zero);
        if (!disposed) timer.Change(System.Threading.Timeout.Infinite, System.Threading.Timeout.Infinite);
        CancelAim(); Motion.Finish(); surface.Hide(); dictionaryWindow.Hide();
        if (preciseTimer) { timeEndPeriod(1); preciseTimer = false; }
        if (contentLayer != null) { contentLayer.Dispose(); contentLayer = null; }
        if (presentation != null) { presentation.Dispose(); presentation = null; }
        maskPixels = animatedMaskPixels = maskRasterPixels = null; framePixels = null; contentKey = null;
        maskKey = null; maskCache.Clear();
        foreach (var sprite in resultSprites.Values) sprite.Dispose(); resultSprites.Clear(); spriteOrder.Clear(); resultGeometry.Clear();
        ClearLabelGlyphs();
        if (filtering) { Application.RemoveMessageFilter(this); filtering = false; }
    }
    public void ShowDictionary()
    {
        if (!Active || window.IsPreview || !window.Visible || window.DictionaryDefinition == null) { dictionaryWindow.Hide(); return; }
        string definition = window.DictionaryDefinition;
        if (readingText.Text != definition) { readingText.Text = definition; readingText.SelectionStart = 0; }
        readingText.BackColor = window.Appearance.Surface; readingText.ForeColor = window.Appearance.Foreground;
        int measured = TextRenderer.MeasureText(definition, readingText.Font, new Size((int)(272 * window.LayoutScale), int.MaxValue), TextFormatFlags.WordBreak).Height;
        int bodyHeight = Math.Min(232, Math.Max(96, (int)Math.Ceiling(measured / window.LayoutScale)));
        readingText.ScrollBars = measured > bodyHeight * window.LayoutScale ? ScrollBars.Vertical : ScrollBars.None;
        dictionaryWindow.ClientSize = new Size((int)(336 * window.LayoutScale), (int)((bodyHeight + 88) * window.LayoutScale));
        readingText.SetBounds((int)(32 * window.LayoutScale), (int)(52 * window.LayoutScale), (int)(272 * window.LayoutScale), (int)(bodyHeight * window.LayoutScale));
        var area = Screen.FromControl(window).WorkingArea;
        int x = window.Right + (int)(8 * window.LayoutScale), y = window.Top;
        if (x + dictionaryWindow.Width > area.Right - 12)
        {
            x = window.Left - dictionaryWindow.Width - (int)(8 * window.LayoutScale);
            if (x < area.Left + 12) { x = window.Left + (window.Width - dictionaryWindow.Width) / 2; y = window.Bottom + (int)(8 * window.LayoutScale); }
        }
        dictionaryWindow.Location = TokcatLauncherWindow.Constrain(new Point(x, y), dictionaryWindow.Size);
        bool newlyShown = !dictionaryWindow.Visible;
        if (newlyShown) dictionaryWindow.Show(window);
        var word = TokcatLauncherTranslationInput.Parse(window.Query.Text);
        dictionaryWindow.RefreshSurface(word == null ? window.Query.Text : word.Text);
        if (newlyShown)
        {
            int start = window.Query.SelectionStart, length = window.Query.SelectionLength;
            window.Activate(); window.Query.Focus(); window.Query.Select(start, length); lostActivation = false;
        }
    }
    public Bitmap Render()
    {
        var image = new Bitmap(Math.Max(1, window.Width), Math.Max(1, window.Height), PixelFormat.Format32bppPArgb);
        try { RenderInto(image); return image; }
        catch { image.Dispose(); throw; }
    }
    void RenderInto(Bitmap image)
    {
        EnsureMask(image.Size);
        if (Motion.IsAnimating)
        {
            PaintFog(image);
            using (var g = Graphics.FromImage(image))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                g.ScaleTransform(Scale, Scale); g.TranslateTransform((float)Motion.Extent, (float)Motion.Extent);
                DrawMovingGlows(g); DrawContents(g); DrawInput(g);
            }
            return;
        }
        bool status = Aiming || window.RadialError || (window.Query.DisplayText.Length > 0 && Items.Length == 0);
        string key = string.Join("|", new object[] { iconRevision, window.Appearance.IsLight, Aiming, Reading, AimIndex,
            window.Results.SelectedIndex, window.RadialError, status, status ? window.Hint.Text : "", Motion.Flow, Motion.Phase }) +
            string.Join(";", Motion.Entries.Select(e => string.Join(":", new object[] { e.Item.Title, e.Item.Kind, e.Id == "web-search", e.Item.App == null ? "" : e.Item.App.Target,
                e.Pose.Radius, e.Pose.Angle, e.Pose.Span, e.Pose.Opacity, e.Pose.Compression })));
        if (contentLayer == null || contentLayer.Size != image.Size || contentKey != key)
        {
            if (contentLayer == null || contentLayer.Size != image.Size)
            {
                if (contentLayer != null) contentLayer.Dispose();
                contentLayer = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppPArgb);
            }
            // Soft effects contain no fine detail. Rasterize and blur them at
            // quarter size, then draw crisp glyphs at the actual display scale.
            float detail = Motion.IsAnimating ? 0.125f : 0.25f;
            using (var glow = new Bitmap(Math.Max(1, (int)Math.Ceiling(image.Width * detail)), Math.Max(1, (int)Math.Ceiling(image.Height * detail)), PixelFormat.Format32bppPArgb))
            {
                using (var g = Graphics.FromImage(glow))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias; g.ScaleTransform(Scale * detail, Scale * detail); g.TranslateTransform((float)Motion.Extent, (float)Motion.Extent);
                    DrawGlows(g);
                }
                Blur(glow, Math.Max(1, (int)Math.Round(7 * Scale * detail)));
                using (var g = Graphics.FromImage(contentLayer)) { g.CompositingMode = CompositingMode.SourceCopy; g.InterpolationMode = InterpolationMode.Bilinear; g.DrawImage(glow, new Rectangle(Point.Empty, image.Size)); }
            }
            using (var g = Graphics.FromImage(contentLayer))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                g.ScaleTransform(Scale, Scale); g.TranslateTransform((float)Motion.Extent, (float)Motion.Extent); DrawContents(g);
            }
            contentKey = key; ContentBuildCount++;
        }
        PaintFog(image);
        using (var g = Graphics.FromImage(image))
        {
            g.DrawImageUnscaled(contentLayer, 0, 0);
            g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.ScaleTransform(Scale, Scale); g.TranslateTransform((float)Motion.Extent, (float)Motion.Extent);
            DrawInput(g);
            if (Aiming) DrawRay(g);
        }
    }
    static void Blur(Bitmap image, int radius)
    {
        var bounds = new Rectangle(Point.Empty, image.Size);
        var data = image.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
        try
        {
            int width = image.Width, height = image.Height, stride = data.Stride;
            byte[] pixels = new byte[stride * height], scratch = new byte[stride * height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            // Three separable box passes approximate the Mac Gaussian blur.
            int box = Math.Max(1, (int)Math.Round(radius * 0.58)), size = box * 2 + 1;
            for (int pass = 0; pass < 3; pass++)
            {
                for (int y = 0; y < height; y++) for (int c = 0; c < 4; c++)
                {
                    int sum = 0; for (int k = 0; k <= box && k < width; k++) sum += pixels[y * stride + k * 4 + c];
                    for (int x = 0; x < width; x++) { scratch[y * stride + x * 4 + c] = (byte)(sum / size); if (x - box >= 0) sum -= pixels[y * stride + (x - box) * 4 + c]; if (x + box + 1 < width) sum += pixels[y * stride + (x + box + 1) * 4 + c]; }
                }
                for (int x = 0; x < width; x++) for (int c = 0; c < 4; c++)
                {
                    int sum = 0; for (int k = 0; k <= box && k < height; k++) sum += scratch[k * stride + x * 4 + c];
                    for (int y = 0; y < height; y++) { pixels[y * stride + x * 4 + c] = (byte)(sum / size); if (y - box >= 0) sum -= scratch[(y - box) * stride + x * 4 + c]; if (y + box + 1 < height) sum += scratch[(y + box + 1) * stride + x * 4 + c]; }
                }
            }
            Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
        }
        finally { image.UnlockBits(data); }
    }
    void DrawGlows(Graphics g)
    {
        var style = window.Appearance;
        using (var inputGlow = Sector(76, 34, Math.PI, Math.PI * 2))
        using (var glow = new SolidBrush(Color.FromArgb(Aiming ? 30 : 13, style.Accent))) g.FillPath(glow, inputGlow);
        foreach (var entry in Motion.Entries)
        {
            var pose = entry.Pose; int index = Array.FindIndex(Items, r => r.Key == entry.Id);
            bool selected = index >= 0 && (Aiming ? AimIndex == index : window.Results.SelectedIndex == index);
            double span = pose.Span * (1 - pose.Compression * 0.12);
            using (var path = Sector(pose.Radius, 34, pose.Angle - span / 2 + 0.022, pose.Angle + span / 2 - 0.022))
            using (var fill = new SolidBrush(Color.FromArgb((int)(pose.Opacity * (selected ? 36 : Aiming ? 17 : 8)), style.Pink))) g.FillPath(fill, path);
        }
        foreach (var link in Motion.Bridges)
        {
            using (var path = Sector(link.Radius, 34, link.Start, link.End))
            using (var fill = new SolidBrush(Color.FromArgb((int)(255 * link.Opacity * (0.14 + Math.Cos(Motion.Phase + link.Start * 2) * 0.04)), style.Accent))) g.FillPath(fill, path);
        }
    }
    void DrawMovingGlows(Graphics g)
    {
        var style = window.Appearance; var items = Items;
        StrokeGlow(g, 76, Math.PI, Math.PI, style.Accent, 13);
        foreach (var entry in Motion.Entries)
        {
            var p = entry.Pose; if (p.Opacity <= 0.003) continue;
            int index = Array.FindIndex(items, r => r.Key == entry.Id);
            bool selected = index >= 0 && window.Results.SelectedIndex == index;
            double span = p.Span * (1 - p.Compression * 0.12);
            StrokeGlow(g, p.Radius, p.Angle - span / 2 + 0.022, Math.Max(0.01, span - 0.044), style.Pink, p.Opacity * (selected ? 36 : 8));
        }
        foreach (var link in Motion.Bridges)
            StrokeGlow(g, link.Radius, link.Start, link.End - link.Start, style.Accent, 255 * link.Opacity * (0.14 + Math.Cos(Motion.Phase + link.Start * 2) * 0.04));
    }
    static void StrokeGlow(Graphics g, double radius, double start, double span, Color color, double opacity)
    {
        float r = (float)radius;
        // Broad, faint strokes feather the moving glow without filtering a
        // full-window bitmap. The detailed settled glow remains cached.
        for (int layer = 0; layer < 3; layer++)
        {
            int alpha = (int)Math.Min(255, Math.Max(0, opacity * (layer == 0 ? 0.15 : layer == 1 ? 0.28 : 0.5)));
            if (alpha == 0) continue;
            using (var pen = new Pen(Color.FromArgb(alpha, color), 50 - layer * 8))
                g.DrawArc(pen, -r, -r, r * 2, r * 2, (float)(start * 180 / Math.PI), (float)(span * 180 / Math.PI));
        }
    }
    // A small stroked-arc mask replaces per-pixel trigonometry at full size.
    // Its alpha is cached; text and icons remain at the native display scale.
    void EnsureMask(Size size)
    {
        bool centerFog = Aiming || (window.Query.DisplayText.Length > 0 && Items.Length == 0) || window.RadialError;
        bool animated = Motion.IsAnimating;
        string geometry = size.Width + ":" + size.Height + ":" + Scale + ":" + Motion.Extent + ":" + centerFog + ":" + animated + ":" +
            string.Join(";", Motion.Bands.Select(b => string.Join(",", new object[] { b.Pose.Radius, b.Pose.Angle, b.Pose.Span, b.Pose.Opacity })));
        if (maskPixels != null && maskKey == geometry) return;
        maskKey = geometry;
        if (!animated && maskCache.TryGetValue(geometry, out maskPixels)) return;
        int length = size.Width * size.Height;
        if (animated)
        {
            if (animatedMaskPixels == null || animatedMaskPixels.Length != length) animatedMaskPixels = new byte[length];
            maskPixels = animatedMaskPixels;
        }
        else maskPixels = new byte[length];
        MaskBuildCount++;
        float detail = animated ? 0.125f : 0.25f;
        using (var small = new Bitmap(Math.Max(1, (int)Math.Ceiling(size.Width * detail)), Math.Max(1, (int)Math.Ceiling(size.Height * detail)), PixelFormat.Format32bppPArgb))
        {
            using (var g = Graphics.FromImage(small))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.ScaleTransform(Scale * detail, Scale * detail); g.TranslateTransform((float)Motion.Extent, (float)Motion.Extent);
                using (var pen = new Pen(Color.White, 46)) g.DrawArc(pen, -76, -76, 152, 152, 180, 180);
                foreach (var band in Motion.Bands)
                {
                    var p = band.Pose; float r = (float)p.Radius;
                    using (var pen = new Pen(Color.FromArgb((int)(255 * Math.Min(1, Math.Max(0, p.Opacity))), Color.White), 46))
                        g.DrawArc(pen, -r, -r, r * 2, r * 2, (float)((p.Angle - p.Span / 2) * 180 / Math.PI), (float)(p.Span * 180 / Math.PI));
                }
                if (centerFog) using (var fill = new SolidBrush(Color.White)) g.FillEllipse(fill, -34, -34, 68, 68);
            }
            Blur(small, Math.Max(1, (int)Math.Round(8 * Scale * detail)));
            // Only alpha is needed. Upsample the blurred mask directly instead
            // of scaling an ARGB bitmap and reading all four channels back.
            var data = small.LockBits(new Rectangle(Point.Empty, small.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            try
            {
                int stride = data.Stride;
                if (maskRasterPixels == null || maskRasterPixels.Length != stride * small.Height) maskRasterPixels = new byte[stride * small.Height];
                Marshal.Copy(data.Scan0, maskRasterPixels, 0, maskRasterPixels.Length);
                int shift = animated ? 3 : 2, step = 1 << shift;
                int smallWidth = small.Width, smallHeight = small.Height;
                int width = size.Width, height = size.Height;
                for (int y = 0; y < height; y++)
                {
                    int sy = Math.Max(0, y - step / 2), top = sy >> shift;
                    int bottom = Math.Min(top + 1, smallHeight - 1), wy = sy & (step - 1);
                    int output = y * width;
                    int left = maskRasterPixels[top * stride + 3] * (step - wy) + maskRasterPixels[bottom * stride + 3] * wy;
                    for (int x = 0; x < step / 2 && x < width; x++) maskPixels[output++] = (byte)(left >> shift);
                    for (int column = 1; output < (y + 1) * width; column++)
                    {
                        int source = Math.Min(column, smallWidth - 1) * 4 + 3;
                        int right = maskRasterPixels[top * stride + source] * (step - wy) + maskRasterPixels[bottom * stride + source] * wy;
                        int count = Math.Min(step, (y + 1) * width - output);
                        int value = left * step;
                        for (int i = 0; i < count; i++, value += right - left) maskPixels[output++] = (byte)(value >> (2 * shift));
                        left = right;
                    }
                }
            }
            finally { small.UnlockBits(data); }
        }
        if (!animated) { if (maskCache.Count >= 8) maskCache.Clear(); maskCache[geometry] = maskPixels; }
    }
    void PaintFog(Bitmap image)
    {
        int width = image.Width, height = image.Height;
        Color color = window.Appearance.Surface;
        if (fogColor != color.ToArgb())
        {
            fogColor = color.ToArgb();
            for (int alpha = 0; alpha < 256; alpha++) fogPalette[alpha] = (alpha << 24) | (color.R * alpha / 255 << 16) | (color.G * alpha / 255 << 8) | (color.B * alpha / 255);
        }
        var data = image.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            int stride = data.Stride / 4, length = stride * height;
            if (framePixels == null || framePixels.Length != length) framePixels = new int[length];
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
                framePixels[y * stride + x] = fogPalette[maskPixels[y * width + x]];
            Marshal.Copy(framePixels, 0, data.Scan0, length);
        }
        finally { image.UnlockBits(data); }
    }
    void DrawInput(Graphics g)
    {
        var style = window.Appearance;
        string query = window.Query.DisplayText;
        using (var font = new Font(query.Length == 0 ? "Microsoft YaHei UI" : "Consolas", query.Length == 0 ? 14 : 18, FontStyle.Regular, GraphicsUnit.Pixel))
            DrawArcText(g, query.Length == 0 ? "输入内容…" : query, 76, Math.PI * 1.5, Math.PI * 0.76, font, query.Length == 0 ? style.Secondary : style.Foreground, true,
                query.Length == 0 ? -1 : window.Query.Composing ? window.Query.CompositionStart + window.Query.CompositionCaret : window.Query.SelectionStart,
                window.Query.Composing ? 0 : window.Query.SelectionLength, window.Query.Composing ? window.Query.CompositionStart : -1, (window.Query.CompositionText ?? "").Length);
    }
    void DrawContents(Graphics g)
    {
        var style = window.Appearance;
        string query = window.Query.DisplayText;
        // Paint fading labels beneath the newly actionable choices.
        var items = accessibleItems;
        foreach (var entry in Motion.Entries.OrderByDescending(e => e.Departing))
        {
            var pose = entry.Pose; int index = Array.FindIndex(items, r => r.Key == entry.Id);
            bool selected = index >= 0 && (Aiming ? AimIndex == index : window.Results.SelectedIndex == index);
            if (pose.Opacity <= 0.003) continue;
            bool upper = Math.Sin(pose.Angle) < -0.001;
            TokcatRadialMotion.Pose reference;
            if (!resultGeometry.TryGetValue(entry.Id, out reference)) reference = new TokcatRadialMotion.Pose { Radius = 76 + entry.Ring * 56, Span = pose.Span };
            var sprite = GetResultSprite(entry, reference, upper, selected);
            var state = g.Save();
            g.RotateTransform((float)(pose.Angle * 180 / Math.PI));
            g.TranslateTransform((float)pose.Radius, 0);
            g.ScaleTransform((float)(1 - pose.Compression * 0.13), (float)(Math.Max(0.05, pose.Span / reference.Span) * (1 + pose.Compression * 0.13)));
            if (sprite.Text.PointCount > 0) using (var brush = new SolidBrush(Color.FromArgb((int)(255 * Math.Min(1, pose.Opacity)), sprite.TextColor))) g.FillPath(brush, sprite.Text);
            g.TranslateTransform(-12, 0); g.RotateTransform(upper ? 90 : -90);
            var iconBounds = new Rectangle(-sprite.Size / 2 - 2, -sprite.Size / 2 - 2, sprite.Size + 4, sprite.Size + 4);
            if (pose.Opacity >= 0.999) g.DrawImage(sprite.Icon, iconBounds);
            else using (var attributes = new ImageAttributes())
            {
                var matrix = new ColorMatrix(); matrix.Matrix33 = (float)Math.Min(1, pose.Opacity); attributes.SetColorMatrix(matrix);
                g.DrawImage(sprite.Icon, iconBounds, 0, 0, sprite.Icon.Width, sprite.Icon.Height, GraphicsUnit.Pixel, attributes);
            }
            g.Restore(state);
        }
        if (Aiming || (query.Length > 0 && Items.Length == 0) || window.RadialError)
        {
            string text = Reading ? "滚动阅读" : Aiming ? (Items.Length == 0 ? "松开返回" : "松开执行") : window.Hint.Text;
            using (var font = new Font("Microsoft YaHei UI", 9, GraphicsUnit.Pixel)) DrawArcText(g, text, 29, Math.PI / 2, Math.PI * 0.92, font, window.RadialError ? style.Pink : style.Secondary, false, -1, 0, -1, 0);
        }
    }
    // Build curved glyph outlines and small icons once in local coordinates.
    // Reflow transforms these paths without reshaping text or filtering large
    // rotated bitmaps on every frame.
    ResultSprite GetResultSprite(TokcatRadialMotion.Entry entry, TokcatRadialMotion.Pose reference, bool upper, bool selected)
    {
        var style = window.Appearance;
        int revision = System.Threading.Volatile.Read(ref iconRevision);
        string key = string.Join("|", new object[] { entry.Item.Title, entry.Item.Kind, entry.Id == "web-search", entry.Item.App == null ? "" : entry.Item.App.Target,
            style.IsLight, selected, upper, Scale, reference.Radius, reference.Span });
        ResultSprite sprite;
        if (resultSprites.TryGetValue(key, out sprite))
        {
            if (sprite.IconRevision != revision && entry.Item.Kind == "application" && entry.Item.App != null)
            {
                using (var g = Graphics.FromImage(sprite.Icon)) { g.Clear(Color.Transparent); g.ScaleTransform(Scale, Scale); g.TranslateTransform(2, 2); icons.Draw(g, entry.Item.App, new Rectangle(0, 0, sprite.Size, sprite.Size)); }
                sprite.IconRevision = revision;
            }
            return sprite;
        }
        double radius = reference.Radius, span = Math.Max(0.08, reference.Span - 0.09);
        int size = entry.Id == "web-search" ? 14 : 18;
        var image = new Bitmap(Math.Max(1, (int)Math.Ceiling((size + 4) * Scale)), Math.Max(1, (int)Math.Ceiling((size + 4) * Scale)), PixelFormat.Format32bppPArgb);
        GraphicsPath text = null;
        try
        {
            using (var g = Graphics.FromImage(image))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                g.ScaleTransform(Scale, Scale); g.TranslateTransform(2, 2);
                if (entry.Item.Kind == "application" && entry.Item.App != null) icons.Draw(g, entry.Item.App, new Rectangle(0, 0, size, size));
                else { var state = g.Save(); g.TranslateTransform(size / 2f, size / 2f); DrawSymbol(g, entry.Item.Kind, size, selected ? style.Accent : style.Pink); g.Restore(state); }
                using (var font = new Font("Microsoft YaHei UI", entry.Id == "web-search" ? 11 : 13, FontStyle.Regular, GraphicsUnit.Pixel))
                    text = BuildArcOutline(g, entry.Item.Title, radius, span, font, upper);
            }
            sprite = new ResultSprite { Icon = image, Text = text, Size = size, IconRevision = revision, TextColor = selected ? style.Foreground : style.Secondary };
            while (resultSprites.Count >= 192)
            {
                string oldest = spriteOrder.Dequeue(); resultSprites[oldest].Dispose(); resultSprites.Remove(oldest);
            }
            resultSprites.Add(key, sprite); spriteOrder.Enqueue(key); SpriteBuildCount++; return sprite;
        }
        catch { image.Dispose(); if (text != null) text.Dispose(); throw; }
    }
    void ClearLabelGlyphs()
    {
        foreach (var glyph in labelGlyphs.Values) glyph.Outline.Dispose();
        labelGlyphs.Clear();
    }
    GraphicsPath BuildArcOutline(Graphics g, string text, double radius, double span, Font font, bool upper)
    {
        var result = new GraphicsPath();
        var glyphs = new List<string>();
        var enumerator = StringInfo.GetTextElementEnumerator(text ?? "");
        using (var format = (StringFormat)StringFormat.GenericTypographic.Clone())
        using (var emojiFont = new Font("Segoe UI Emoji", font.Size, font.Style, GraphicsUnit.Pixel))
        using (var regularFamily = font.FontFamily)
        using (var emojiFamily = emojiFont.FontFamily)
        {
            format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            while (enumerator.MoveNext())
            {
                string glyph = enumerator.GetTextElement();
                int scalar = char.IsSurrogatePair(glyph, 0) ? char.ConvertToUtf32(glyph, 0) : glyph[0];
                bool join = glyphs.Count > 0 && (glyph[0] == '\u200d' || glyphs.Last().EndsWith("\u200d", StringComparison.Ordinal) || (scalar >= 0x1f3fb && scalar <= 0x1f3ff) || (scalar >= 0x1f1e6 && scalar <= 0x1f1ff && glyphs.Last().Length == 2 && char.ConvertToUtf32(glyphs.Last(), 0) >= 0x1f1e6 && char.ConvertToUtf32(glyphs.Last(), 0) <= 0x1f1ff));
                if (join) glyphs[glyphs.Count - 1] += glyph; else glyphs.Add(glyph);
            }
            // Only the visible prefix fits on the arc. Share glyph outlines
            // across the multiple application labels introduced by one key.
            if (labelGlyphs.Count > 512) ClearLabelGlyphs();
            var shapes = new List<LabelGlyph>();
            double width = 0, textRadius = radius + 12;
            string keyPrefix = Scale + "|" + font.Size + "|";
            format.Alignment = StringAlignment.Center; format.LineAlignment = StringAlignment.Center;
            foreach (string glyph in glyphs)
            {
                string key = keyPrefix + glyph;
                LabelGlyph shape;
                if (!labelGlyphs.TryGetValue(key, out shape))
                {
                    bool emoji = char.IsSurrogatePair(glyph, 0);
                    var glyphFont = emoji ? emojiFont : font;
                    shape = new LabelGlyph { Advance = Math.Max(2, g.MeasureString(glyph, glyphFont, PointF.Empty, format).Width + 0.35), Outline = new GraphicsPath() };
                    shape.Outline.AddString(glyph, emoji ? emojiFamily : regularFamily, (int)glyphFont.Style, glyphFont.Size, PointF.Empty, format);
                    labelGlyphs.Add(key, shape);
                }
                if (shapes.Count > 0 && width + shape.Advance > span * textRadius) break;
                shapes.Add(shape); width += shape.Advance;
            }
            double offset = -width / 2;
            for (int i = 0; i < shapes.Count; i++)
            {
                double a = (upper ? 1 : -1) * (offset + shapes[i].Advance / 2) / textRadius;
                using (var path = (GraphicsPath)shapes[i].Outline.Clone())
                using (var transform = new Matrix())
                {
                    transform.Translate((float)(Math.Cos(a) * textRadius - radius), (float)(Math.Sin(a) * textRadius));
                    transform.Rotate((float)((a + (upper ? Math.PI / 2 : -Math.PI / 2)) * 180 / Math.PI));
                    if (path.PointCount > 0) { path.Transform(transform); result.AddPath(path, false); }
                }
                offset += shapes[i].Advance;
            }
        }
        return result;
    }
    static GraphicsPath Sector(double radius, double thickness, double start, double end)
    {
        var path = new GraphicsPath(); var points = new List<PointF>();
        for (int i = 0; i <= 48; i++) { double a = start + (end - start) * i / 48; points.Add(new PointF((float)(Math.Cos(a) * (radius + thickness / 2)), (float)(Math.Sin(a) * (radius + thickness / 2)))); }
        for (int i = 48; i >= 0; i--) { double a = start + (end - start) * i / 48; points.Add(new PointF((float)(Math.Cos(a) * (radius - thickness / 2)), (float)(Math.Sin(a) * (radius - thickness / 2)))); }
        path.AddPolygon(points.ToArray()); return path;
    }
    public static void DrawArcText(Graphics g, string text, double radius, double angle, double maxSpan, Font font, Color color, bool upper, int caret, int selection, int markedStart, int markedLength)
    {
        if (string.IsNullOrEmpty(text)) return;
        var glyphs = new List<string>(); var advances = new List<double>(); var ranges = new List<int>();
        var enumerator = StringInfo.GetTextElementEnumerator(text);
        using (var format = (StringFormat)StringFormat.GenericTypographic.Clone())
        using (var emojiFont = new Font("Segoe UI Emoji", font.Size, font.Style, GraphicsUnit.Pixel))
        {
            format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            while (enumerator.MoveNext())
            {
                string glyph = enumerator.GetTextElement();
                int scalar = char.IsSurrogatePair(glyph, 0) ? char.ConvertToUtf32(glyph, 0) : glyph[0];
                bool join = glyphs.Count > 0 && (glyph[0] == '\u200d' || glyphs.Last().EndsWith("\u200d", StringComparison.Ordinal) || (scalar >= 0x1f3fb && scalar <= 0x1f3ff) || (scalar >= 0x1f1e6 && scalar <= 0x1f1ff && glyphs.Last().Length == 2 && char.ConvertToUtf32(glyphs.Last(), 0) >= 0x1f1e6 && char.ConvertToUtf32(glyphs.Last(), 0) <= 0x1f1ff));
                if (join) glyphs[glyphs.Count - 1] += glyph;
                else { glyphs.Add(glyph); ranges.Add(enumerator.ElementIndex); }
            }
            foreach (string glyph in glyphs) advances.Add(Math.Max(2, g.MeasureString(glyph, char.IsSurrogatePair(glyph, 0) ? emojiFont : font, PointF.Empty, format).Width + 0.35));
            int first = 0, last = glyphs.Count; double width = advances.Sum();
            while (width > maxSpan * radius && last - first > 1)
            {
                if (caret < 0 || caret < (ranges[first] + ranges[last - 1]) / 2) { last--; width -= advances[last]; }
                else { width -= advances[first]; first++; }
            }
            double offset = -width / 2; double? insertion = null;
            for (int i = first; i < last; i++)
            {
                if (caret == ranges[i]) insertion = offset;
                double a = angle + (upper ? 1 : -1) * (offset + advances[i] / 2) / radius;
                var state = g.Save(); g.TranslateTransform((float)(Math.Cos(a) * radius), (float)(Math.Sin(a) * radius)); g.RotateTransform((float)((a + (upper ? Math.PI / 2 : -Math.PI / 2)) * 180 / Math.PI));
                int end = i + 1 < ranges.Count ? ranges[i + 1] : text.Length;
                if (selection > 0 && end > caret && ranges[i] < caret + selection)
                    using (var fill = new SolidBrush(Color.FromArgb((int)(color.A * 0.22), color))) g.FillRectangle(fill, (float)-advances[i] / 2, -font.Size * 0.65f, (float)advances[i], font.Size * 1.3f);
                using (var brush = new SolidBrush(color)) { format.Alignment = StringAlignment.Center; format.LineAlignment = StringAlignment.Center; g.DrawString(glyphs[i], char.IsSurrogatePair(glyphs[i], 0) ? emojiFont : font, brush, PointF.Empty, format); }
                if (markedStart >= 0 && markedLength > 0 && end > markedStart && ranges[i] < markedStart + markedLength) using (var pen = new Pen(color, 0.8f)) g.DrawLine(pen, (float)-advances[i] / 2, font.Size * 0.62f, (float)advances[i] / 2, font.Size * 0.62f);
                g.Restore(state); offset += advances[i]; if (caret == end) insertion = offset;
            }
            if (caret >= 0 && insertion.HasValue)
            {
                double a = angle + (upper ? 1 : -1) * insertion.Value / radius;
                using (var pen = new Pen(color, 1)) g.DrawLine(pen, (float)(Math.Cos(a) * (radius - font.Size * 0.65)), (float)(Math.Sin(a) * (radius - font.Size * 0.65)), (float)(Math.Cos(a) * (radius + font.Size * 0.65)), (float)(Math.Sin(a) * (radius + font.Size * 0.65)));
            }
        }
    }
    static void DrawSymbol(Graphics g, string kind, int size, Color color)
    {
        using (var pen = new Pen(color, 1.3f))
        {
            float r = size / 2f - 1;
            switch (kind)
            {
                case "calculation": g.DrawLine(pen, -r, -3, r, -3); g.DrawLine(pen, -r, 3, r, 3); break;
                case "terminal": g.DrawLines(pen, new[] { new PointF(-r, -5), new PointF(-1, 0), new PointF(-r, 5) }); g.DrawLine(pen, 1, 5, r, 5); break;
                case "settings": g.DrawEllipse(pen, -r, -r, r * 2, r * 2); g.DrawEllipse(pen, -3, -3, 6, 6); for (int i = 0; i < 8; i++) { double a = i * Math.PI / 4; g.DrawLine(pen, (float)Math.Cos(a) * r, (float)Math.Sin(a) * r, (float)Math.Cos(a) * (r + 2), (float)Math.Sin(a) * (r + 2)); } break;
                case "translate": case "translation": case "web-translations":
                    g.DrawRectangle(pen, -r, -r + 1, size - 2, size - 5); g.DrawLines(pen, new[] { new PointF(-3, r - 4), new PointF(-3, r), new PointF(1, r - 4) });
                    using (var font = new Font("Microsoft YaHei UI", 9, GraphicsUnit.Pixel)) using (var brush = new SolidBrush(color)) g.DrawString("文", font, brush, -6, -7); break;
                case "definition": g.DrawRectangle(pen, -5, -6, 10, 13); g.DrawLines(pen, new[] { new PointF(-7, 4), new PointF(-7, -8), new PointF(3, -8) }); break;
                case "file": g.DrawRectangle(pen, -5, -7, 10, 14); g.DrawLine(pen, -2, -2, 3, -2); g.DrawLine(pen, -2, 2, 3, 2); break;
                default: g.DrawEllipse(pen, -r, -r, r * 2, r * 2); g.DrawEllipse(pen, -r / 2, -r, r, r * 2); g.DrawLine(pen, -r, 0, r, 0); break;
            }
        }
    }
    void DrawRay(Graphics g)
    {
        Color[] spectrum = { Color.FromArgb(112,89,255), Color.FromArgb(31,158,255), Color.FromArgb(38,240,240), Color.FromArgb(133,255,179), Color.FromArgb(255,217,97), Color.FromArgb(255,102,133), Color.FromArgb(242,87,214) };
        PointF vector = AimVector; double length = Math.Sqrt(vector.X * vector.X + vector.Y * vector.Y);
        if (length > 2)
        {
            if (AimIndex >= 0) { double reach = Math.Max(length, Layout.Slots.First(s => s.Index == AimIndex).Radius); vector = new PointF((float)(vector.X * reach / length), (float)(vector.Y * reach / length)); length = reach; }
            float spread = (float)Math.Min(4.5, length * 0.023);
            for (int i = 0; i < spectrum.Length; i++)
            {
                float shift = (i - 3) / 3f * spread;
                PointF end = new PointF(vector.X - vector.Y / (float)length * shift, vector.Y + vector.X / (float)length * shift);
                using (var path = new GraphicsPath())
                {
                    path.AddBezier(PointF.Empty, new PointF(vector.X * 0.413f, vector.Y * 0.413f), new PointF(vector.X * 0.747f, vector.Y * 0.747f), end);
                    using (var glow = new Pen(Color.FromArgb(window.Appearance.IsLight ? 60 : 80, spectrum[i]), 3.2f)) g.DrawPath(glow, path);
                    using (var gradient = new LinearGradientBrush(PointF.Empty, end, Color.FromArgb(13, spectrum[i]), Color.FromArgb(217, spectrum[i]))) using (var pen = new Pen(gradient, 0.8f)) g.DrawPath(pen, path);
                }
            }
            using (var pen = new Pen(window.Appearance.IsLight ? window.Appearance.Accent : Color.White, 1)) g.DrawLine(pen, PointF.Empty, vector);
            using (var brush = new SolidBrush(window.Appearance.Accent)) g.FillEllipse(brush, vector.X - 1.6f, vector.Y - 1.6f, 3.2f, 3.2f);
        }
        for (int i = 0; i < spectrum.Length; i++) using (var pen = new Pen(spectrum[i], 0.9f)) g.DrawArc(pen, -12, -12, 24, 24, i * 360f / spectrum.Length, 360f / spectrum.Length + 1);
        using (var brush = new SolidBrush(window.Appearance.IsLight ? window.Appearance.Accent : Color.White)) g.FillEllipse(brush, -1.5f, -1.5f, 3, 3);
    }
    public void Dispose()
    {
        if (disposed) return;
        Stop(); disposed = true; Application.ApplicationExit -= OnExit; timer.Dispose(); surface.Dispose(); dictionaryWindow.Dispose();
    }
}

sealed class TokcatRadialReadingWindow : Form
{
    readonly TokcatLauncherBackdrop backdrop = new TokcatLauncherBackdrop();
    TokcatLauncherTextBox body;
    TokcatLauncherWindow launcher;
    Bitmap texture;
    int paintedRevision = -1;
    string paintedWord;
    Point paintedLocation;
    Color paintedColor;
    [DllImport("user32.dll")] static extern bool SetWindowDisplayAffinity(IntPtr handle, uint affinity);
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x80; return p; } }
    public TokcatRadialReadingWindow() { FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual; BackColor = TransparencyKey = TokcatLauncherRadial.TransparentKey; }
    public void Initialize(TokcatLauncherTextBox editor, TokcatLauncherWindow launcher)
    {
        this.launcher = launcher; body = editor; Controls.Add(editor);
        editor.BackgroundPainter = delegate(Graphics g, Rectangle target, Point origin) {
            using (var brush = new SolidBrush(launcher.Appearance.Surface)) g.FillRectangle(brush, target);
            if (texture != null) g.DrawImage(texture, target, new Rectangle(origin.X + MarginX, origin.Y + MarginY, target.Width, target.Height), GraphicsUnit.Pixel);
        };
        VisibleChanged += delegate { if (!Visible) { backdrop.Hide(); body.ReleaseBackground(); if (texture != null) { texture.Dispose(); texture = null; } } };
    }
    int MarginX { get { return (int)(16 * launcher.LayoutScale); } }
    int MarginY { get { return (int)(26 * launcher.LayoutScale); } }
    public bool SetCaptureAffinity(uint affinity)
    {
        return SetWindowDisplayAffinity(Handle, affinity) && SetWindowDisplayAffinity(backdrop.Handle, affinity);
    }
    public IntPtr[] CaptureHandles { get { return new[] { Handle, backdrop.Handle }; } }
    protected override void WndProc(ref Message message)
    {
        if (body != null && (message.Msg == 0x0133 || message.Msg == 0x0138) && message.LParam == body.Handle)
        {
            IntPtr brush = body.PaintBackground(message.WParam);
            if (brush != IntPtr.Zero) { message.Result = brush; return; }
        }
        base.WndProc(ref message);
    }
    public void RefreshSurface(string word)
    {
        if (!Visible) return;
        int revision = launcher.Appearance.BackgroundRevision;
        if (texture != null && paintedRevision == revision && paintedWord == word && paintedLocation == Location && paintedColor == launcher.Appearance.Foreground && texture.Size == new Size(Width + MarginX * 2, Height + MarginY * 2)) return;
        try
        {
            var next = new Bitmap(Width + MarginX * 2, Height + MarginY * 2, PixelFormat.Format32bppArgb);
            try
            {
                using (var g = Graphics.FromImage(next))
                {
                    launcher.Appearance.PaintDesktop(g, new Rectangle(Point.Empty, next.Size), new Rectangle(Left - MarginX, Top - MarginY, next.Width, next.Height));
                }
                if (texture != null) texture.Dispose(); texture = next; next = null;
            }
            finally { if (next != null) next.Dispose(); }
            using (var frame = FeatheredFrame())
            {
                using (var g = Graphics.FromImage(frame))
                using (var heading = new Font("Microsoft YaHei UI", 16 * launcher.LayoutScale, FontStyle.Bold, GraphicsUnit.Pixel))
                using (var footer = new Font("Microsoft YaHei UI", 10 * launcher.LayoutScale, GraphicsUnit.Pixel))
                using (var text = new SolidBrush(launcher.Appearance.Foreground))
                using (var secondary = new SolidBrush(launcher.Appearance.Secondary))
                using (var format = new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap })
                {
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    g.DrawString(word, heading, text, new RectangleF(MarginX + 32 * launcher.LayoutScale, MarginY + 20 * launcher.LayoutScale, 272 * launcher.LayoutScale, 24 * launcher.LayoutScale), format);
                    g.DrawString("按住 Ctrl · 滚轮上下阅读", footer, secondary, new PointF(MarginX + 32 * launcher.LayoutScale, MarginY + Height - 36 * launcher.LayoutScale));
                }
                backdrop.Update(frame, new Point(Left - MarginX, Top - MarginY), Handle);
            }
            paintedWord = word; paintedLocation = Location; paintedColor = launcher.Appearance.Foreground; paintedRevision = revision;
            body.BackgroundVersion++; body.Invalidate();
        }
        catch (Exception error)
        {
            if (!(error is System.ComponentModel.Win32Exception) && !(error is ExternalException) && !(error is ArgumentException)) throw;
            backdrop.Hide();
        }
    }
    Bitmap FeatheredFrame()
    {
        var frame = new Bitmap(texture.Width, texture.Height, PixelFormat.Format32bppPArgb);
        var bounds = new Rectangle(Point.Empty, texture.Size);
        var from = texture.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var to = frame.LockBits(bounds, ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var pixels = new byte[from.Stride * from.Height]; Marshal.Copy(from.Scan0, pixels, 0, pixels.Length);
            for (int y = 0; y < frame.Height; y++) for (int x = 0; x < frame.Width; x++)
            {
                double horizontal = Math.Min(1, Math.Min(x, frame.Width - 1 - x) / (42.0 * launcher.LayoutScale));
                double vertical = Math.Min(1, Math.Min(y, frame.Height - 1 - y) / (22.0 * launcher.LayoutScale));
                int alpha = (int)(255 * horizontal * vertical); int offset = y * from.Stride + x * 4;
                pixels[offset] = (byte)(pixels[offset] * alpha / 255); pixels[offset + 1] = (byte)(pixels[offset + 1] * alpha / 255); pixels[offset + 2] = (byte)(pixels[offset + 2] * alpha / 255); pixels[offset + 3] = (byte)alpha;
            }
            Marshal.Copy(pixels, 0, to.Scan0, pixels.Length);
        }
        finally { texture.UnlockBits(from); frame.UnlockBits(to); }
        return frame;
    }
    protected override void Dispose(bool disposing) { if (disposing) { backdrop.Dispose(); if (texture != null) { texture.Dispose(); texture = null; } } base.Dispose(disposing); }
}

sealed class TokcatRadialSurface : Form
{
    public TokcatLauncherRadial Radial;
    public TokcatLauncherPointerFollower Follower;
    delegate IntPtr MouseHook(int code, IntPtr message, IntPtr data);
    MouseHook hookCallback;
    IntPtr mouseHook;
    readonly Timer fallback = new Timer { Interval = 1 };
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int type, MouseHook callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct Blend { public byte Operation, Flags, Alpha, Format; }
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr window, IntPtr destination, ref Point point, ref Size size, IntPtr source, ref Point origin, int key, ref Blend blend, int flags);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x80000 | 0x08000000 | 0x80; return p; } }
    public TokcatRadialSurface()
    {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual; AccessibleName = "赛博轮盘";
        fallback.Tick += delegate { if (Follower != null) Follower.PublishPointer(Cursor.Position); };
    }
    public void ConfigurePointer(bool enabled)
    {
        if (!enabled || !Visible || Follower == null || !Follower.ReceiveNativeInput)
        {
            fallback.Stop();
            if (mouseHook != IntPtr.Zero) { UnhookWindowsHookEx(mouseHook); mouseHook = IntPtr.Zero; }
            if (Follower != null) Follower.MouseHookActive = false;
            return;
        }
        if (mouseHook != IntPtr.Zero || fallback.Enabled) return;
        hookCallback = delegate(int code, IntPtr message, IntPtr data)
        {
            if (code >= 0 && message.ToInt32() == 0x0200)
                Follower.PublishPointer(new Point(Marshal.ReadInt32(data), Marshal.ReadInt32(data, 4)));
            return CallNextHookEx(mouseHook, code, message, data);
        };
        mouseHook = SetWindowsHookEx(14, hookCallback, GetModuleHandle(null), 0);
        Follower.MouseHookActive = mouseHook != IntPtr.Zero;
        if (mouseHook == IntPtr.Zero) fallback.Start();
    }
    protected override void WndProc(ref Message message)
    {
        if (Follower != null)
        {
            switch (message.Msg)
            {
                case TokcatLauncherPointerFollower.PresentMessage: Follower.PresentOnNativeThread(); return;
                case TokcatLauncherPointerFollower.MoveMessage: Follower.MoveOnNativeThread(); return;
                case TokcatLauncherPointerFollower.ConfigureMessage: Follower.ConfigureOnNativeThread(); return;
                case TokcatLauncherPointerFollower.HideMessage: Follower.HideOnNativeThread(); return;
                case TokcatLauncherPointerFollower.CloseMessage: ConfigurePointer(false); Hide(); Application.ExitThread(); return;
            }
        }
        base.WndProc(ref message);
    }
    protected override void Dispose(bool disposing) { if (disposing) { ConfigurePointer(false); fallback.Dispose(); } base.Dispose(disposing); }
    protected override AccessibleObject CreateAccessibilityInstance() { return new WheelAccessibility(this); }
    sealed class WheelAccessibility : ControlAccessibleObject
    {
        readonly TokcatRadialSurface surface;
        public WheelAccessibility(TokcatRadialSurface surface) : base(surface) { this.surface = surface; }
        public override AccessibleRole Role { get { return AccessibleRole.List; } }
        public override int GetChildCount() { return surface.Radial == null ? 0 : surface.Radial.AccessibleItems.Length; }
        public override AccessibleObject GetChild(int index)
        {
            var items = surface.Radial == null ? new TokcatLauncherResult[0] : surface.Radial.AccessibleItems;
            return index >= 0 && index < items.Length ? new ChoiceAccessibility(this, surface.Radial, items[index].Key) : null;
        }
        public override AccessibleObject GetSelected() { return surface.Radial == null ? null : GetChild(surface.Radial.SelectedIndex); }
        public override AccessibleObject HitTest(int x, int y)
        {
            if (surface.Radial == null) return null;
            var radial = surface.Radial;
            string id = radial.Motion.HitTest(new PointF((x - radial.ScreenOrigin.X) / radial.Scale - (float)radial.Motion.Extent, (y - radial.ScreenOrigin.Y) / radial.Scale - (float)radial.Motion.Extent));
            int index = Array.FindIndex(radial.AccessibleItems, r => r.Key == id); return index < 0 ? null : GetChild(index);
        }
    }
    sealed class ChoiceAccessibility : AccessibleObject
    {
        readonly AccessibleObject parent;
        readonly TokcatLauncherRadial radial;
        readonly string id;
        public ChoiceAccessibility(AccessibleObject parent, TokcatLauncherRadial radial, string id) { this.parent = parent; this.radial = radial; this.id = id; }
        public override AccessibleObject Parent { get { return parent; } }
        public override AccessibleRole Role { get { return AccessibleRole.PushButton; } }
        public override string Name { get { var item = radial.AccessibleItems.FirstOrDefault(r => r.Key == id); return item == null ? "" : item.Title + "，" + item.Detail; } set { } }
        public override string DefaultAction { get { return "执行"; } }
        public override AccessibleStates State
        {
            get { int index = Array.FindIndex(radial.AccessibleItems, r => r.Key == id); return AccessibleStates.Focusable | AccessibleStates.Selectable | (index == radial.SelectedIndex ? AccessibleStates.Selected : AccessibleStates.None); }
        }
        public override Rectangle Bounds
        {
            get
            {
                var entry = radial.Motion.Entries.FirstOrDefault(e => e.Id == id && !e.Departing);
                if (entry == null) return Rectangle.Empty;
                PointF p = entry.Pose.Center; float size = (float)Math.Min(entry.Pose.Span * entry.Pose.Radius, 80) * radial.Scale;
                return new Rectangle((int)(radial.ScreenOrigin.X + (p.X + radial.Motion.Extent) * radial.Scale - size / 2), (int)(radial.ScreenOrigin.Y + (p.Y + radial.Motion.Extent) * radial.Scale - 17 * radial.Scale), (int)size, (int)(34 * radial.Scale));
            }
        }
        public override void DoDefaultAction() { radial.PerformAccessibleItem(id); }
    }
    public void MoveTo(Point point) { if (Visible) SetWindowPos(Handle, IntPtr.Zero, point.X, point.Y, 0, 0, 0x0010 | 0x0001 | 0x0004 | 0x0200 | 0x0400); }
    public void Update(Bitmap image, Point point, IntPtr launcher)
    {
        IntPtr dc = CreateCompatibleDC(IntPtr.Zero), bitmap = image.GetHbitmap(Color.FromArgb(0)), previous = SelectObject(dc, bitmap);
        try
        {
            Size size = image.Size; Point origin = Point.Empty; var blend = new Blend { Alpha = 255, Format = 1 };
            if (!UpdateLayeredWindow(Handle, IntPtr.Zero, ref point, ref size, dc, ref origin, 0, ref blend, 2)) throw new System.ComponentModel.Win32Exception();
            if (!Visible) { Show(); SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0010 | 0x0001 | 0x0002); }
        }
        finally { SelectObject(dc, previous); DeleteObject(bitmap); DeleteDC(dc); }
    }
}
