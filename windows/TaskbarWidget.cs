using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;
using Microsoft.Win32;

// A real WS_CHILD window owned by Explorer's taskbar. No top-level overlay.
public sealed class TokcatTaskbarWidget : NativeWindow, IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; public Rectangle Rect { get { return Rectangle.FromLTRB(Left, Top, Right, Bottom); } } }
    [StructLayout(LayoutKind.Sequential)] struct PAINTSTRUCT { public IntPtr Hdc; public int Erase; public RECT Paint; public int Restore, IncUpdate; [MarshalAs(UnmanagedType.ByValArray, SizeConst=32)] public byte[] Reserved; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool SetWindowText(IntPtr h, string text);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int command);
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint colorKey, byte alpha, uint flags);
    [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr h, IntPtr rect, bool erase);
    [DllImport("user32.dll")] static extern IntPtr BeginPaint(IntPtr h, out PAINTSTRUCT paint);
    [DllImport("user32.dll")] static extern bool EndPaint(IntPtr h, ref PAINTSTRUCT paint);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    const int WS_CHILD = 0x40000000, WS_CLIPSIBLINGS = 0x04000000;
    sealed class Layout { public IntPtr Host; public Rectangle Bounds; public Rectangle[] Occupied; public uint Dpi; public DateTime At; public string Error; }
    readonly object gate = new object();
    readonly ManualResetEvent stop = new ManualResetEvent(false);
    readonly System.Windows.Forms.Timer timer;
    Layout latest;
    volatile bool enabled, disposed;
    bool started;
    string first = "tokcat", second = "";
    string[] states = new string[0];
    public ContextMenuStrip Menu { get; set; }
    public event EventHandler Clicked;
    public string Status { get; private set; }
    public bool Embedded { get { return Handle != IntPtr.Zero && GetParent(Handle) == PrimaryTaskbar && IsWindowVisible(Handle); } }
    public static IntPtr PrimaryTaskbar { get { return FindWindow("Shell_TrayWnd", null); } }
    public static string Caption(IntPtr h) { var text=new System.Text.StringBuilder(1024); GetWindowText(h,text,text.Capacity); return text.ToString(); }
    public static IntPtr FindEmbeddedWidget() { IntPtr h=IntPtr.Zero; var parent=PrimaryTaskbar; while(parent!=IntPtr.Zero && (h=FindWindowEx(parent,h,null,null))!=IntPtr.Zero) if(Caption(h).StartsWith("tokcat: ",StringComparison.Ordinal)) return h; return IntPtr.Zero; }
    public static Rectangle BoundsOf(IntPtr h) { RECT r; return h!=IntPtr.Zero && GetWindowRect(h,out r) ? r.Rect : Rectangle.Empty; }
    public IntPtr ParentHandle { get { return Handle == IntPtr.Zero ? IntPtr.Zero : GetParent(Handle); } }
    public bool Visible { get { return Handle != IntPtr.Zero && IsWindowVisible(Handle); } }
    public bool OverlapsButtons { get { Layout layout; lock(gate) { layout=latest; } var rect=WindowBounds; if(layout==null || layout.Occupied==null) return false; foreach(var button in layout.Occupied) if(rect.IntersectsWith(button)) return true; return false; } }
    public Rectangle WindowBounds { get { RECT r; return Handle != IntPtr.Zero && GetWindowRect(Handle, out r) ? r.Rect : Rectangle.Empty; } }
    public static Rectangle TaskbarBounds { get { RECT r; return GetWindowRect(PrimaryTaskbar, out r) ? r.Rect : Rectangle.Empty; } }
    public static void EnableDpiAwareness() { try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) {} }

    public TokcatTaskbarWidget() {
        timer = new System.Windows.Forms.Timer(); timer.Interval = 750;
        timer.Tick += delegate { RefreshAttachment(); };
        Status = "Waiting for taskbar layout";
    }
    public void SetEnabled(bool value) {
        enabled = value;
        if (value && !started) {
            started = true; var thread = new Thread(Observe); thread.IsBackground = true; thread.Name = "tokcat taskbar layout"; thread.SetApartmentState(ApartmentState.MTA); thread.Start();
        }
        if (value) { timer.Start(); RefreshAttachment(); }
        else { timer.Stop(); if (Handle != IntPtr.Zero) ShowWindow(Handle, 0); Status = "Hidden"; }
    }
    public void SetContent(string[] dots, string line1, string line2) {
        states = dots ?? new string[0]; first = line1 ?? ""; second = line2 ?? "";
        if (Handle != IntPtr.Zero) { SetWindowText(Handle,"tokcat: "+first+" | "+second); InvalidateRect(Handle, IntPtr.Zero, false); }
    }

    // Rectangles are physical screen coordinates; supports negative monitor origins.
    // Do not resize Explorer's windows or cover occupied buttons to make room.
    public static Rectangle FindSlot(Rectangle bar, Rectangle[] occupied, int wanted, int minimum, int margin) {
        if (bar.Height < 20 || bar.Width < bar.Height || minimum <= 0) return Rectangle.Empty;
        var blocks = new List<Rectangle>();
        foreach (var r in occupied ?? new Rectangle[0]) {
            if (!bar.IntersectsWith(r) || r.Width <= 0) continue;
            blocks.Add(Rectangle.FromLTRB(Math.Max(bar.Left, r.Left-margin), bar.Top, Math.Min(bar.Right, r.Right+margin), bar.Bottom));
        }
        blocks.Sort(delegate(Rectangle a, Rectangle b) { return a.Left.CompareTo(b.Left); });
        int left = bar.Left + margin; Rectangle result = Rectangle.Empty;
        foreach (var block in blocks) {
            if (block.Left-left >= minimum) { int width = Math.Min(wanted, block.Left-left); result = new Rectangle(block.Left-width, bar.Top, width, bar.Height); }
            left = Math.Max(left, block.Right);
        }
        if (bar.Right-margin-left >= minimum) { int width = Math.Min(wanted, bar.Right-margin-left); result = new Rectangle(bar.Right-margin-width, bar.Top, width, bar.Height); }
        return result;
    }
    void Observe() {
        EnableDpiAwareness();
        try {
            do {
                if (!enabled) { if(stop.WaitOne(750)) break; continue; }
                var layout = new Layout { At=DateTime.UtcNow, Error="Taskbar unavailable" };
                try {
                    layout.Host = PrimaryTaskbar; RECT rect;
                    if (layout.Host != IntPtr.Zero && GetWindowRect(layout.Host, out rect)) {
                        layout.Bounds = rect.Rect; layout.Dpi = GetDpiForWindow(layout.Host); if (layout.Dpi == 0) layout.Dpi = 96;
                        var blocks = new List<Rectangle>();
                        var root = AutomationElement.FromHandle(layout.Host);
                        var condition = new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button), new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem));
                        foreach (AutomationElement element in root.FindAll(TreeScope.Descendants, condition)) {
                            try {
                                var current = element.Current; var b = current.BoundingRectangle;
                                if (!current.IsOffscreen && !b.IsEmpty && b.Width > 0 && b.Height > 0) blocks.Add(Rectangle.FromLTRB((int)b.Left, (int)b.Top, (int)Math.Ceiling(b.Right), (int)Math.Ceiling(b.Bottom)));
                            } catch (ElementNotAvailableException) {}
                        }
                        IntPtr tray = FindWindowEx(layout.Host, IntPtr.Zero, "TrayNotifyWnd", null);
                        if (tray != IntPtr.Zero && GetWindowRect(tray, out rect)) blocks.Add(rect.Rect);
                        // Respect other native taskbar widgets (for example TrafficMonitor).
                        IntPtr child=IntPtr.Zero;
                        while ((child=FindWindowEx(layout.Host,child,null,null))!=IntPtr.Zero) {
                            if (child==Handle || !IsWindowVisible(child) || !GetWindowRect(child,out rect)) continue;
                            var cls=new System.Text.StringBuilder(256); GetClassName(child,cls,cls.Capacity);
                            string name=cls.ToString();
                            if (name=="ReBarWindow32" || name=="MSTaskSwWClass" || name=="MSTaskListWClass" || name=="Windows.UI.Composition.DesktopWindowContentBridge" || name=="XamlExplorerHostIslandWindow") continue;
                            if(rect.Rect.Width<layout.Bounds.Width*0.7 && rect.Rect.Height<=layout.Bounds.Height+4) blocks.Add(rect.Rect);
                        }
                        // If accessibility returns no buttons, do not guess an empty taskbar.
                        if (blocks.Count > 0) { layout.Occupied = blocks.ToArray(); layout.Error = null; }
                        else layout.Error = "Taskbar layout unavailable";
                    }
                } catch (Exception ex) { layout.Error = ex.GetType().Name; }
                lock (gate) { latest = layout; }
            } while (!stop.WaitOne(1500));
        } finally { stop.Dispose(); }
    }
    public void RefreshAttachment() {
        if (!enabled || disposed) return;
        Layout layout; lock (gate) { layout = latest; }
        if (layout == null || layout.Error != null || (DateTime.UtcNow-layout.At).TotalSeconds > 8 || !IsWindow(layout.Host) || PrimaryTaskbar != layout.Host) {
            if (Handle != IntPtr.Zero) ShowWindow(Handle, 0);
            Status = layout == null ? "Waiting for taskbar layout" : layout.Error ?? "Taskbar layout expired"; return;
        }
        double scale = layout.Dpi/96.0;
        var slot = FindSlot(layout.Bounds, layout.Occupied, (int)(480*scale), (int)(270*scale), (int)Math.Ceiling(8*scale));
        if (slot.IsEmpty) { if (Handle != IntPtr.Zero) ShowWindow(Handle, 0); Status = "No free taskbar space"; return; }
        try { Attach(layout.Host, new Rectangle(slot.Left-layout.Bounds.Left, slot.Top-layout.Bounds.Top, slot.Width, slot.Height)); }
        catch (Exception ex) { if (Handle!=IntPtr.Zero) ShowWindow(Handle,0); Status="Taskbar embedding failed: "+ex.GetType().Name; }
    }
    void Attach(IntPtr parent, Rectangle clientBounds) {
        if (Handle != IntPtr.Zero && GetParent(Handle) != parent) DestroyHandle();
        if (Handle == IntPtr.Zero) {
            CreateHandle(new CreateParams { Caption="tokcat taskbar", Parent=parent, Style=WS_CHILD|WS_CLIPSIBLINGS, ExStyle=0x08080080 });
            if(!SetLayeredWindowAttributes(Handle,0,255,2)) { DestroyHandle(); Status="Taskbar rendering failed"; return; }
        }
        SetWindowText(Handle,"tokcat: "+first+" | "+second);
        if (GetParent(Handle) != parent) { ShowWindow(Handle, 0); Status="Taskbar embedding failed"; return; }
        if (!SetWindowPos(Handle, IntPtr.Zero, clientBounds.X, clientBounds.Y, clientBounds.Width, clientBounds.Height, 0x0010|0x0040)) { Status="Taskbar positioning failed"; ShowWindow(Handle, 0); return; }
        Status="Embedded"; InvalidateRect(Handle, IntPtr.Zero, false);
    }
    public void AttachForTest(IntPtr parent, Rectangle bounds) { Attach(parent, bounds); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x000F) {
            PAINTSTRUCT paint; IntPtr dc = BeginPaint(Handle, out paint);
            try { using (var graphics=Graphics.FromHdc(dc)) Paint(graphics); } finally { EndPaint(Handle, ref paint); }
            m.Result=IntPtr.Zero; return;
        }
        if (m.Msg == 0x0014) { m.Result=new IntPtr(1); return; }
        if (m.Msg == 0x0202) { var handler=Clicked; if (handler!=null) handler(this,EventArgs.Empty); m.Result=IntPtr.Zero; return; }
        if (m.Msg == 0x0205) { Point p; if (Menu!=null && GetCursorPos(out p)) Menu.Show(p); m.Result=IntPtr.Zero; return; }
        if (m.Msg == 0x0021) { m.Result=new IntPtr(3); return; } // MA_NOACTIVATE
        base.WndProc(ref m);
    }
    void Paint(Graphics g) {
        var bounds=WindowBounds; if (bounds.IsEmpty) return;
        uint dpi=GetDpiForWindow(Handle); float scale=(dpi==0?96:dpi)/96f;
        bool light=false;
        try { using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) light=key!=null && Convert.ToInt32(key.GetValue("SystemUsesLightTheme",0))!=0; } catch {}
        var background=light?Color.FromArgb(240,240,240):Color.FromArgb(32,32,32); var foreground=light?Color.FromArgb(20,20,20):Color.White;
        g.Clear(background); g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        for (int i=0;i<Math.Min(6,states.Length);i++) {
            var color=Color.Gray; switch(states[i]) { case "running":color=Color.Goldenrod;break;case "waiting":case "approval":color=Color.OrangeRed;break;case "failed":color=Color.Red;break;case "stalled":color=Color.DarkOrange;break;case "completed":color=Color.ForestGreen;break; }
            using(var brush=new SolidBrush(color)) g.FillEllipse(brush,(3+(i%3)*10)*scale,(bounds.Height/scale/2-10+(i/3)*11)*scale,8*scale,8*scale);
        }
        int left=(int)(38*scale), padding=(int)(3*scale); int half=bounds.Height/2;
        using(var font=new Font("Microsoft YaHei UI",11*scale,FontStyle.Regular,GraphicsUnit.Pixel)) {
            var flags=TextFormatFlags.NoPadding|TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine|TextFormatFlags.VerticalCenter|TextFormatFlags.NoPrefix;
            TextRenderer.DrawText(g,first,font,new Rectangle(left,padding,Math.Max(0,bounds.Width-left-4),half-padding),foreground,background,flags);
            TextRenderer.DrawText(g,second,font,new Rectangle(left,half,Math.Max(0,bounds.Width-left-4),half-padding),foreground,background,flags);
        }
    }
    public void Dispose() { if (disposed) return; disposed=true; timer.Stop(); timer.Dispose(); if(started) stop.Set(); else stop.Dispose(); if(Handle!=IntPtr.Zero) DestroyHandle(); }
}
