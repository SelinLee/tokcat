using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public sealed class TokcatLauncherWindow : Form
{
    public readonly TokcatLauncherTextBox Query = new TokcatLauncherTextBox();
    public readonly ListBox Results = new ListBox();
    public readonly Label Hint = new Label();
    public event EventHandler Submitted;
    public event EventHandler ContainingFolderRequested;
    public event EventHandler HistoryOlder;
    public event EventHandler HistoryNewer;
    public event EventHandler PositionChanged;
    readonly TokcatLauncherInputPanel input = new TokcatLauncherInputPanel();
    readonly Color selection;
    readonly TokcatLauncherIcons icons = new TokcatLauncherIcons();
    readonly Color[] palette;
    readonly Label searchIcon;
    readonly TokcatLauncherPlaceholder placeholder = new TokcatLauncherPlaceholder();
    readonly TokcatLauncherTextBox definition = new TokcatLauncherTextBox();
    readonly Button webTranslation = new Button();
    readonly TokcatLauncherSurfacePanel dictionaryPanel = new TokcatLauncherSurfacePanel();
    public readonly TokcatLauncherAppearance Appearance;
    public readonly TokcatLauncherRadial Radial;
    public bool RadialError { get; private set; }
    string activeDefinition;
    bool radialApplied;
    Point regularLocation;
    public TokcatLauncherResult[] RadialSearchResults = new TokcatLauncherResult[0];
    public bool IsPreview { get; set; }
    public event EventHandler WebTranslationRequested;
    public float LayoutScale { get { return DeviceDpi / 96f; } }
    public int InputHeight { get { return input.Height; } }
    public bool ClassicIsLight { get { return palette[1].GetBrightness() > 0.5f; } }
    public string DictionaryDefinition { get { return activeDefinition; } }
    public int DefinitionHeight { get { return dictionaryPanel.Height; } }

    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr handle, int message, IntPtr parameter, IntPtr data);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLong(IntPtr handle, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong(IntPtr handle, int index, int value);

    public TokcatLauncherWindow(Color[] palette)
    {
        this.palette = palette;
        Text = "tokcat · 快速启动";
        AccessibleName = Text;
        FormBorderStyle = FormBorderStyle.None;
        KeyPreview = true;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Microsoft YaHei UI", 11);
        BackColor = palette[0]; ForeColor = palette[2]; selection = palette[4];
        ClientSize = new Size(560, 56);
        Padding = new Padding(1);
        input.Launcher = this;
        input.Dock = DockStyle.Top; input.Height = 54; input.BackColor = palette[1]; input.Cursor = Cursors.SizeAll;
        input.AccessibleName = "拖动空白处以移动快速启动框";
        input.MouseDown += BeginDrag;
        var icon = new Label { Text = "⌕", Font = new Font("Segoe UI", 24), ForeColor = palette[3], TextAlign = ContentAlignment.MiddleCenter, Dock = DockStyle.Left, Width = 48, Cursor = Cursors.SizeAll };
        icon.AccessibleName = "拖动以移动快速启动框";
        icon.Name = "SearchIcon";
        icon.MouseDown += BeginDrag;
        searchIcon = icon;
        Query.BorderStyle = BorderStyle.None;
        Query.Launcher = this;
        Query.Cursor = Cursors.IBeam;
        Query.MaxLength = 8192;
        Query.Font = new Font("Microsoft YaHei UI", 16.5f);
        Query.BackColor = palette[1]; Query.ForeColor = palette[2];
        Query.AccessibleName = "搜索应用、文件、算式、网站或命令";
        Query.SetBounds(48, 0, 492, Query.PreferredHeight); Query.Anchor = AnchorStyles.Left | AnchorStyles.Top;
        placeholder.Text = "搜索应用、文件、算式、网站或命令"; placeholder.Font = Query.Font;
        placeholder.Cursor = Cursors.IBeam; placeholder.AccessibleName = placeholder.Text;
        placeholder.MouseDown += delegate { Query.Focus(); Query.SelectionStart = 0; };
        input.Layout += delegate
        {
            if (Appearance != null && Appearance.IsRadial) { LayoutRadialEditor(); return; }
            Query.SetBounds(searchIcon.Width, (input.ClientSize.Height - Query.PreferredHeight) / 2,
                Math.Max(1, input.ClientSize.Width - searchIcon.Width - (int)(16 * LayoutScale)), Query.PreferredHeight);
            placeholder.Bounds = new Rectangle(Query.Left + 2, Query.Top, Math.Max(1, Query.Width - 2), Query.Height);
        };
        Query.TextChanged += delegate { UpdatePlaceholder(); };
        Query.CompositionChanged += delegate { UpdatePlaceholder(); };
        input.Controls.Add(Query); input.Controls.Add(icon); input.Controls.Add(placeholder); placeholder.BringToFront();
        Hint.Dock = DockStyle.Bottom; Hint.Height = 0; Hint.Visible = false;
        Hint.Font = new Font("Microsoft YaHei UI", 9); Hint.ForeColor = palette[3];
        Hint.AutoEllipsis = true;
        Results.Dock = DockStyle.Fill; Results.BorderStyle = BorderStyle.None;
        Results.BackColor = palette[1]; Results.ForeColor = palette[2];
        Results.DrawMode = DrawMode.OwnerDrawFixed; Results.ItemHeight = 44; Results.IntegralHeight = false;
        Results.AccessibleName = "快速启动搜索结果";
        Results.DrawItem += DrawResult;
        icons.Changed += delegate
        {
            try { if (IsHandleCreated && !IsDisposed) BeginInvoke((Action)delegate { if (!IsDisposed) Results.Invalidate(); }); }
            catch (InvalidOperationException) { }
        };
        Results.DoubleClick += delegate { Submit(); };
        dictionaryPanel.Dock = DockStyle.Fill; dictionaryPanel.Visible = false; dictionaryPanel.Padding = new Padding(14, 4, 14, 6);
        dictionaryPanel.Launcher = this; definition.Launcher = this;
        definition.Multiline = true; definition.ReadOnly = true; definition.ScrollBars = ScrollBars.Vertical;
        definition.Dock = DockStyle.Fill; definition.BorderStyle = BorderStyle.None; definition.Font = new Font("Microsoft YaHei UI", 10);
        definition.AccessibleName = "本地词典释义，回车复制";
        webTranslation.Text = "网页翻译"; webTranslation.Dock = DockStyle.Bottom; webTranslation.Height = 28;
        webTranslation.Click += delegate { if (WebTranslationRequested != null) WebTranslationRequested(this, EventArgs.Empty); };
        dictionaryPanel.Controls.Add(definition); dictionaryPanel.Controls.Add(webTranslation);
        Controls.Add(dictionaryPanel); Controls.Add(Results); Controls.Add(Hint); Controls.Add(input);
        KeyDown += QueryKeyDown;
        Deactivate += delegate { if (!IsPreview) { if (Appearance != null && Appearance.IsRadial && Radial != null) Radial.NotifyDeactivated(); else Hide(); } };
        FormClosing += delegate(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        };
        MouseDown += BeginDrag;
        ResizeEnd += delegate
        {
            Location = Constrain(Location, Size);
            if (PositionChanged != null) PositionChanged(this, EventArgs.Empty);
        };
        // Background catalog results need a UI dispatch target before the launcher is first shown.
        CreateHandle();
        Appearance = new TokcatLauncherAppearance(this);
        Radial = new TokcatLauncherRadial(this, icons);
        ApplyColors();
    }

    public void ApplyColors()
    {
        bool cyber = Appearance != null && Appearance.IsCyber;
        Color surface = cyber ? Appearance.Surface : palette[1];
        Color text = cyber ? Appearance.Foreground : palette[2];
        Color secondary = cyber ? Appearance.Secondary : palette[3];
        BackColor = cyber ? surface : palette[0];
        input.BackColor = surface; Query.BackColor = surface; Query.ForeColor = text;
        Results.BackColor = surface; Results.ForeColor = text; ForeColor = text;
        searchIcon.ForeColor = cyber ? Appearance.Accent : secondary;
        searchIcon.BackColor = Color.Transparent;
        Hint.ForeColor = secondary; Hint.BackColor = cyber ? Color.Transparent : surface;
        placeholder.ForeColor = secondary; placeholder.BackColor = cyber ? Color.Transparent : surface;
        dictionaryPanel.BackColor = surface; definition.BackColor = surface; definition.ForeColor = text;
        webTranslation.BackColor = surface; webTranslation.ForeColor = text;
        Padding = new Padding(cyber ? 0 : Math.Max(1, (int)LayoutScale));
        bool radial = Appearance != null && Appearance.IsRadial;
        if (radial)
        {
            if (!radialApplied)
            {
                regularLocation = Location;
                // Keep the native editor focusable for IME and editing while
                // clipping its straight text, caret and system selection fill.
                Query.Region = new Region(Rectangle.Empty);
            }
            TransparencyKey = TokcatLauncherRadial.TransparentKey;
            BackColor = input.BackColor = Query.BackColor = Query.ForeColor = TransparencyKey;
            input.Dock = DockStyle.None; searchIcon.Visible = placeholder.Visible = false;
            Results.Visible = Hint.Visible = dictionaryPanel.Visible = false;
            LayoutRadialEditor();
        }
        else if (radialApplied)
        {
            TransparencyKey = Color.Empty; input.Dock = DockStyle.Top; input.Height = (int)Math.Round(54 * LayoutScale);
            var editorRegion = Query.Region; Query.Region = null; if (editorRegion != null) editorRegion.Dispose();
            Query.Font = new Font("Microsoft YaHei UI", 16.5f); Query.TextAlign = HorizontalAlignment.Left;
            searchIcon.Visible = true; Results.Visible = activeDefinition == null; dictionaryPanel.Visible = activeDefinition != null;
            ClientSize = new Size((int)Math.Round(560 * LayoutScale), input.Height + (Query.TextLength > 0 ? (int)(24 * LayoutScale) : 0) + Results.Items.Count * Results.ItemHeight + Padding.Vertical);
            Location = Constrain(regularLocation, Size);
            Hint.Visible = Query.TextLength > 0; Hint.Height = Hint.Visible ? (int)(24 * LayoutScale) : 0;
            UpdatePlaceholder();
        }
        if (radialApplied != radial && Radial != null)
        {
            // The wheel already uses a per-pixel composed surface. Compositing
            // the transparent editor host again can cause a native paint loop
            // when its owned dictionary window opens.
            int style = GetWindowLong(Handle, -20);
            SetWindowLong(Handle, -20, radial ? style & ~0x02000000 : style | 0x02000000);
            radialApplied = radial; Radial.Configure();
        }
        if (radial && Radial != null) Radial.Invalidate();
        UpdateShape();
        Invalidate(true);
    }

    protected override void OnSizeChanged(EventArgs e) { base.OnSizeChanged(e); UpdateShape(); }

    void UpdateShape()
    {
        var previous = Region;
        if (Appearance != null && Appearance.IsCyber) Region = null;
        else if (Width > 0 && Height > 0)
        {
            int diameter = Math.Min(Math.Min(Width, Height), Math.Max(2, (int)(20 * LayoutScale)));
            using (var shape = new System.Drawing.Drawing2D.GraphicsPath())
            {
                shape.AddArc(0, 0, diameter, diameter, 180, 90);
                shape.AddArc(Width - diameter, 0, diameter, diameter, 270, 90);
                shape.AddArc(Width - diameter, Height - diameter, diameter, diameter, 0, 90);
                shape.AddArc(0, Height - diameter, diameter, diameter, 90, 90); shape.CloseFigure();
                Region = new Region(shape);
            }
        }
        if (previous != null && previous != Region) previous.Dispose();
    }

    void UpdatePlaceholder() { placeholder.Visible = (Appearance == null || !Appearance.IsRadial) && Query.TextLength == 0 && !Query.Composing; }

    public void LayoutRadialEditor()
    {
        if (Radial == null || !Appearance.IsRadial) return;
        float scale = Radial.Scale;
        input.SetBounds((Width - (int)(166 * scale)) / 2, (int)(Height / 2 - 88 * scale), (int)(166 * scale), (int)(28 * scale));
        Query.TextAlign = HorizontalAlignment.Center;
        Query.SetBounds(0, Math.Max(0, (input.Height - Query.PreferredHeight) / 2), input.Width, Query.PreferredHeight);
    }

    public void SubmitRadial() { Submit(); }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        if (Appearance != null && Appearance.IsRadial) e.Graphics.Clear(TokcatLauncherRadial.TransparentKey);
        else if (Appearance != null && Appearance.IsCyber) Appearance.Paint(e.Graphics, ClientRectangle, Point.Empty);
        else base.OnPaintBackground(e);
    }

    protected override void WndProc(ref Message message)
    {
        if (Radial != null && Radial.ProcessFrameMessage(ref message)) return;
        base.WndProc(ref message);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            if (Appearance == null || !Appearance.IsRadial) parameters.ExStyle |= 0x02000000; // Paint classic child controls together.
            return parameters;
        }
    }

    void BeginDrag(object sender, MouseEventArgs e)
    {
        if (IsPreview || e.Button != MouseButtons.Left) return;
        Point point = ((Control)sender).PointToScreen(e.Location);
        int coordinates = (point.X & 0xFFFF) | ((point.Y & 0xFFFF) << 16);
        ReleaseCapture();
        SendMessage(Handle, 0x00A1, new IntPtr(2), new IntPtr(coordinates));
    }

    void QueryKeyDown(object sender, KeyEventArgs e)
    {
        if (IsPreview) return;
        if (Query.Composing) return;
        if (Appearance.IsRadial && e.Modifiers == Keys.None && (e.KeyCode == Keys.Left || e.KeyCode == Keys.Right || e.KeyCode == Keys.Up || e.KeyCode == Keys.Down))
        {
            if ((Query.TextLength == 0 && e.KeyCode == Keys.Up) || (BrowsingHistory && (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down)))
            {
                if (e.KeyCode == Keys.Up && HistoryOlder != null) HistoryOlder(this, EventArgs.Empty);
                else if (e.KeyCode == Keys.Down && HistoryNewer != null) HistoryNewer(this, EventArgs.Empty);
            }
            else Radial.Navigate(e.KeyCode);
            e.Handled = true; e.SuppressKeyPress = true; return;
        }
        if (e.KeyCode == Keys.Escape) Hide();
        else if (e.KeyCode == Keys.Enter && e.Control)
        {
            if (ContainingFolderRequested != null) ContainingFolderRequested(this, EventArgs.Empty);
        }
        else if (e.KeyCode == Keys.Enter) Submit();
        else if (e.KeyCode == Keys.Up && (Query.TextLength == 0 || BrowsingHistory))
        {
            if (HistoryOlder != null) HistoryOlder(this, EventArgs.Empty);
        }
        else if (e.KeyCode == Keys.Down && BrowsingHistory)
        {
            if (HistoryNewer != null) HistoryNewer(this, EventArgs.Empty);
        }
        else if (e.KeyCode == Keys.Up && Results.Items.Count > 0) Results.SelectedIndex = Math.Max(0, Results.SelectedIndex - 1);
        else if (e.KeyCode == Keys.Down && Results.Items.Count > 0) Results.SelectedIndex = Math.Min(Results.Items.Count - 1, Results.SelectedIndex + 1);
        else return;
        e.Handled = true; e.SuppressKeyPress = true;
    }

    public bool BrowsingHistory { get; set; }
    void Submit() { if (Submitted != null) Submitted(this, EventArgs.Empty); }

    void DrawResult(object sender, DrawItemEventArgs e)
    {
        if (e.Index < 0) return;
        var result = (TokcatLauncherResult)Results.Items[e.Index];
        if (Appearance.IsCyber)
        {
            Appearance.Paint(e.Graphics, e.Bounds, new Point(Results.Left, Results.Top + e.Bounds.Top));
            if ((e.State & DrawItemState.Selected) != 0)
                using (var brush = new System.Drawing.Drawing2D.LinearGradientBrush(e.Bounds, Color.FromArgb(48, Appearance.Accent), Color.FromArgb(0, Appearance.Accent), 0f)) e.Graphics.FillRectangle(brush, e.Bounds);
        }
        else using (var brush = new SolidBrush((e.State & DrawItemState.Selected) != 0 ? selection : Results.BackColor)) e.Graphics.FillRectangle(brush, e.Bounds);
        float scale = LayoutScale;
        int padding = (int)Math.Round(14 * scale);
        int textLeft = e.Bounds.Left + padding;
        if (result.Kind == "application" && result.App != null)
        {
            int size = (int)Math.Round(28 * scale);
            icons.Draw(e.Graphics, result.App, new Rectangle(textLeft, e.Bounds.Top + (e.Bounds.Height - size) / 2, size, size));
            textLeft += size + (int)Math.Round(12 * scale);
        }
        int textWidth = Math.Max(0, e.Bounds.Right - textLeft - padding);
        var flags = TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
        TextRenderer.DrawText(e.Graphics, result.Title, Font, new Rectangle(textLeft, e.Bounds.Top + (int)(2 * scale), textWidth, (int)(22 * scale)), ForeColor, flags);
        using (var detailFont = new Font(Font.FontFamily, 9))
            TextRenderer.DrawText(e.Graphics, result.Detail, detailFont, new Rectangle(textLeft, e.Bounds.Top + (int)(25 * scale), textWidth, (int)(17 * scale)), Hint.ForeColor, flags);
    }

    string displayedQuery;
    public void SetResults(IEnumerable<TokcatLauncherResult> results, string hint)
    {
        activeDefinition = null; RadialError = false;
        dictionaryPanel.Visible = false; Results.Visible = !Appearance.IsRadial;
        var selected = Results.SelectedItem as TokcatLauncherResult;
        string selectedKey = displayedQuery == Query.DisplayText && selected != null ? selected.Key : null;
        displayedQuery = Query.DisplayText;
        var visible = (results ?? Enumerable.Empty<TokcatLauncherResult>()).ToArray();
        if (Appearance.IsRadial)
        {
            // Three radii contain 1 + 3 + 5 choices. Reserve the small web
            // search choice instead of letting overflow create a fourth ring.
            var search = visible.FirstOrDefault(r => r.Key == "web-search");
            visible = visible.Where(r => r.Key != "web-search").OrderByDescending(r => r.RadialWeight)
                .Take(TokcatRadialLayout.MaxVisibleResults - (search == null ? 0 : 1))
                .Concat(search == null ? new TokcatLauncherResult[0] : new[] { search }).ToArray();
        }
        Results.BeginUpdate();
        try
        {
            Results.Items.Clear();
            foreach (var result in visible)
            {
                Results.Items.Add(result);
                if (result.Kind == "application") icons.Request(result.App);
            }
            if (Results.Items.Count > 0) Results.SelectedIndex = 0;
            if (selectedKey != null)
                for (int i = 0; i < Results.Items.Count; i++)
                    if (string.Equals(((TokcatLauncherResult)Results.Items[i]).Key, selectedKey, StringComparison.OrdinalIgnoreCase)) { Results.SelectedIndex = i; break; }
        }
        finally { Results.EndUpdate(); }
        SetHint(hint, false);
        FitContent(Results.Items.Count * Results.ItemHeight);
        if (Appearance.IsRadial) Results.Visible = false;
    }

    public void SetHint(string text, bool force)
    {
        Hint.Text = text;
        RadialError = force;
        if (Appearance.IsRadial) { Hint.Visible = false; Hint.Height = 0; Radial.Invalidate(); return; }
        bool show = force || Query.DisplayText.Length > 0;
        Hint.Visible = show;
        Hint.Height = show ? (int)Math.Round(24 * LayoutScale) : 0;
        Hint.Padding = new Padding((int)(12 * LayoutScale), 0, 0, 0);
        if (force) FitContent(dictionaryPanel.Visible ? dictionaryPanel.Height : Results.Items.Count * Results.ItemHeight);
    }

    public void SetDefinition(string text)
    {
        if (Appearance.IsRadial)
        {
            SetResults(new[] {
                new TokcatLauncherResult { Title = "复制释义", Detail = "本地词典", Kind = "definition", Key = "definition", RadialWeight = 1.8 },
                new TokcatLauncherResult { Title = "网页翻译", Detail = "选择翻译方式", Kind = "web-translations", Key = "web-translations", RadialWeight = 0.8 }
            }.Concat(RadialSearchResults), "");
            activeDefinition = text; Radial.ShowDictionary(); return;
        }
        activeDefinition = text;
        Results.Items.Clear(); Results.Visible = false;
        definition.Text = text; definition.SelectionStart = 0;
        int measured = TextRenderer.MeasureText(text, definition.Font, new Size(Math.Max(1, ClientSize.Width - 48), int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl).Height;
        dictionaryPanel.Height = Math.Min((int)(230 * LayoutScale), Math.Max((int)(60 * LayoutScale), measured)) + webTranslation.Height + dictionaryPanel.Padding.Vertical;
        int contentHeight = dictionaryPanel.Height;
        dictionaryPanel.Visible = true;
        SetHint("本地词典 · Enter 复制释义 · 可切换网页翻译", false);
        FitContent(contentHeight);
    }

    void FitContent(int contentHeight)
    {
        if (Appearance.IsRadial) { Radial.Update(true); return; }
        int wantedHeight = input.Height + Hint.Height + contentHeight + Padding.Vertical;
        Height = Math.Min(wantedHeight, Screen.FromPoint(Location).WorkingArea.Height);
        Location = Constrain(Location, Size);
    }

    public static Point Constrain(Point location, Size size)
    {
        Rectangle bounds = Screen.FromPoint(location).WorkingArea;
        return new Point(Math.Max(bounds.Left, Math.Min(location.X, bounds.Right - size.Width)),
            Math.Max(bounds.Top, Math.Min(location.Y, bounds.Bottom - size.Height)));
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { if (Radial != null) Radial.Dispose(); icons.Dispose(); if (Appearance != null) Appearance.Dispose(); }
        base.Dispose(disposing);
    }
}

public sealed class TokcatLauncherResult
{
    public string Title, Detail, Kind, Value, Key, Input;
    public double Score;
    public bool ExactApplication;
    public double RadialWeight = 1;
    public TokcatLauncherApp App;
    public override string ToString() { return Title + " " + Detail; }
}

public sealed class TokcatLauncherIcons : IDisposable
{
    sealed class Entry
    {
        public string Key;
        public Icon Icon;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ShellFileInfo
    {
        public IntPtr Icon;
        public int IconIndex;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHParseDisplayName(string name, IntPtr context, out IntPtr item, uint attributes, out uint foundAttributes);
    [DllImport("shell32.dll", EntryPoint = "SHGetFileInfoW", CharSet = CharSet.Unicode)]
    static extern IntPtr SHGetFileInfo(IntPtr item, uint attributes, out ShellFileInfo info, uint size, uint flags);
    [DllImport("comctl32.dll")] static extern IntPtr ImageList_GetIcon(IntPtr images, int index, uint flags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr reserved, uint flags);
    [DllImport("ole32.dll")] static extern void CoUninitialize();

    readonly object gate = new object();
    readonly Dictionary<string, Entry> cache = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);
    readonly Queue<string> order = new Queue<string>();
    Queue<Entry> pending = new Queue<Entry>();
    readonly AutoResetEvent available = new AutoResetEvent(false);
    bool disposed;
    public event EventHandler Changed;

    public TokcatLauncherIcons()
    {
        var worker = new Thread(LoadPending);
        worker.IsBackground = true;
        worker.SetApartmentState(ApartmentState.STA);
        worker.Start();
    }

    static string ShellTarget(TokcatLauncherApp app)
    {
        return app.Packaged ? @"shell:AppsFolder\" + app.Target : app.Target;
    }

    public void Request(TokcatLauncherApp app)
    {
        if (app == null || string.IsNullOrWhiteSpace(app.Target)) return;
        string target = ShellTarget(app);
        lock (gate)
        {
            if (disposed || cache.ContainsKey(target)) return;
            if (cache.Count >= 128)
            {
                string oldest = order.Dequeue();
                if (cache[oldest].Icon != null) cache[oldest].Icon.Dispose();
                cache.Remove(oldest);
                pending = new Queue<Entry>(pending.Where(entry => cache.ContainsKey(entry.Key)));
            }
            var next = new Entry { Key = target };
            cache.Add(target, next); order.Enqueue(target); pending.Enqueue(next);
            available.Set();
        }
    }

    public bool Draw(Graphics graphics, TokcatLauncherApp app, Rectangle bounds)
    {
        Request(app);
        lock (gate)
        {
            if (disposed) return false;
            Entry entry;
            Icon icon = app != null && cache.TryGetValue(ShellTarget(app), out entry) ? entry.Icon : null;
            graphics.DrawIcon(icon ?? SystemIcons.Application, bounds);
            return icon != null;
        }
    }

    void LoadPending()
    {
        int initialized = CoInitializeEx(IntPtr.Zero, 2);
        try
        {
            while (true)
            {
                Entry next;
                lock (gate)
                {
                    if (disposed) return;
                    next = pending.Count == 0 ? null : pending.Dequeue();
                }
                if (next == null) { available.WaitOne(); continue; }
                Icon icon = initialized >= 0 ? LoadIcon(next.Key) : null;
                lock (gate)
                {
                    Entry current;
                    if (disposed || !cache.TryGetValue(next.Key, out current) || current != next)
                    {
                        if (icon != null) icon.Dispose();
                        continue;
                    }
                    next.Icon = icon;
                }
                var changed = Changed;
                if (changed != null) changed(this, EventArgs.Empty);
            }
        }
        finally
        {
            if (initialized >= 0) CoUninitialize();
            available.Dispose();
        }
    }

    static Icon LoadIcon(string target)
    {
        IntPtr item = IntPtr.Zero;
        IntPtr icon = IntPtr.Zero;
        var info = new ShellFileInfo();
        try
        {
            uint attributes;
            if (SHParseDisplayName(target, IntPtr.Zero, out item, 0, out attributes) < 0 || item == IntPtr.Zero) return null;
            // Use the base shell image so shortcut icons retain custom artwork without arrow overlays.
            IntPtr images = SHGetFileInfo(item, 0, out info, (uint)Marshal.SizeOf(typeof(ShellFileInfo)), 0x4000 | 0x8);
            if (images == IntPtr.Zero) return null;
            icon = ImageList_GetIcon(images, info.IconIndex, 1);
            if (icon == IntPtr.Zero) return null;
            return (Icon)Icon.FromHandle(icon).Clone();
        }
        catch (ExternalException) { return null; }
        catch (ArgumentException) { return null; }
        finally
        {
            if (icon != IntPtr.Zero) DestroyIcon(icon);
            if (item != IntPtr.Zero) Marshal.FreeCoTaskMem(item);
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            foreach (var entry in cache.Values) if (entry.Icon != null) entry.Icon.Dispose();
            cache.Clear(); order.Clear(); pending.Clear();
            available.Set();
        }
    }
}

sealed class TokcatLauncherHotKey : NativeWindow, IDisposable
{
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window, int id);
    public event EventHandler Pressed;
    bool registered;
    public TokcatLauncherHotKey() { CreateHandle(new CreateParams { Caption = "tokcat launcher hotkey", Parent = new IntPtr(-3) }); }
    public bool Register(int modifiers, int key)
    {
        Unregister();
        registered = RegisterHotKey(Handle, 1, (uint)modifiers | 0x4000, (uint)key);
        return registered;
    }
    public void Unregister() { if (registered) UnregisterHotKey(Handle, 1); registered = false; }
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0312 && message.WParam.ToInt32() == 1)
        {
            if (Pressed != null) Pressed(this, EventArgs.Empty);
        }
        base.WndProc(ref message);
    }
    public void Dispose() { Unregister(); DestroyHandle(); }
}

public sealed class TokcatLauncherController : IDisposable
{
    readonly string path;
    readonly Color[] palette;
    readonly bool enableHotKey;
    readonly TokcatLauncherHotKey hotKey;
    readonly System.Windows.Forms.Timer catalogRefresh = new System.Windows.Forms.Timer { Interval = 3 * 60 * 60 * 1000 };
    readonly System.Windows.Forms.Timer fileDebounce = new System.Windows.Forms.Timer { Interval = 180 };
    readonly System.Windows.Forms.Timer dictionaryDebounce = new System.Windows.Forms.Timer { Interval = 150 };
    readonly TokcatLauncherDictionary dictionary = new TokcatLauncherDictionary();
    int dictionaryGeneration;
    string dictionaryQuery, dictionaryDefinition, dictionaryError;
    bool dictionaryPending, prefersWebTranslation;
    string requestedTranslation;
    readonly TokcatEverythingSearch fileSearch;
    TokcatEverythingFile[] fileResults = new TokcatEverythingFile[0];
    string pendingFileQuery, completedFileQuery, fileError;
    TokcatLauncherSettings settings;
    TokcatLauncherIndex index = new TokcatLauncherIndex(new TokcatLauncherApp[0]);
    bool scanning, recalling, configurationValid = true;
    volatile bool disposed;
    int historyCursor = -1;
    string catalogError;
    string observedInput;
    public readonly TokcatLauncherWindow Window;
    public event EventHandler OpenSettings;
    public event EventHandler StatusChanged;
    public string Status { get; private set; }

    public TokcatLauncherController(string path, Color[] palette, bool enableHotKey)
    {
        this.path = path; this.palette = palette; this.enableHotKey = enableHotKey;
        try { settings = TokcatLauncherSettings.Load(path); }
        catch (Exception error) { settings = new TokcatLauncherSettings(); configurationValid = false; Status = "设置读取失败 · " + error.Message; }
        Window = new TokcatLauncherWindow(palette);
        Window.Appearance.Configure(settings.Skin, settings.AutoTextColor);
        fileSearch = new TokcatEverythingSearch();
        Window.VisibleChanged += delegate { if (!Window.Visible && !disposed) { ClearFileQuery(); ClearDictionaryQuery(); } };
        dictionaryDebounce.Tick += delegate { dictionaryDebounce.Stop(); LookupDictionary(); };
        Window.WebTranslationRequested += delegate { ShowWebTranslations(); };
        fileSearch.Completed += delegate(object sender, TokcatEverythingReply reply)
        {
            if (reply.Query != Window.Query.DisplayText.Trim()) return;
            completedFileQuery = reply.Query; fileResults = reply.Files; fileError = reply.Error;
            UpdateResults();
        };
        fileDebounce.Tick += delegate { fileDebounce.Stop(); if (!string.IsNullOrEmpty(pendingFileQuery)) fileSearch.Query(pendingFileQuery); };
        hotKey = new TokcatLauncherHotKey();
        hotKey.Pressed += delegate { if (Window.Visible) Window.Hide(); else Show(); };
        Window.Query.TextChanged += delegate { if (!Window.Query.Composing) InputChanged(); };
        Window.Query.CompositionChanged += delegate { InputChanged(); };
        Window.Submitted += delegate { SubmitSelection(); };
        Window.ContainingFolderRequested += delegate { OpenContainingFolder(); };
        Window.HistoryOlder += delegate { Recall(true); };
        Window.HistoryNewer += delegate { Recall(false); };
        Window.PositionChanged += delegate
        {
            settings.X = Window.Left; settings.Y = Window.Top;
            Save();
        };
        Register();
        catalogRefresh.Tick += delegate { RefreshCatalog(); };
        catalogRefresh.Start();
        RefreshCatalog();
    }

    public string ShortcutText { get { return FormatShortcut(settings.Modifiers, settings.Key); } }
    public bool Enabled { get { return settings.Enabled; } }
    public bool IsIndexing { get { return scanning; } }
    public int IndexedApplicationCount { get { return index.Count; } }
    public static string FormatShortcut(int modifiers, int key)
    {
        string name = key == 32 ? "Space" : ((Keys)key).ToString();
        return ((modifiers & 2) != 0 ? "Ctrl+" : "") + ((modifiers & 1) != 0 ? "Alt+" : "") + ((modifiers & 4) != 0 ? "Shift+" : "") + name;
    }

    void Register()
    {
        hotKey.Unregister();
        if (configurationValid)
        {
            Status = !settings.Enabled || !enableHotKey ? "可通过窗口或托盘打开快速启动。" :
                hotKey.Register(settings.Modifiers, settings.Key) ? "按 " + ShortcutText + " 打开快速启动框" : "快捷键被占用，请在启动器设置中更换。";
        }
        Changed();
    }

    void Changed() { if (StatusChanged != null) StatusChanged(this, EventArgs.Empty); }
    void Save()
    {
        if (!configurationValid) return;
        try { settings.Save(path); }
        catch (Exception error) { Status = "设置保存失败 · " + error.Message; Changed(); }
    }

    public void Show()
    {
        if (disposed) return;
        historyCursor = -1; Window.BrowsingHistory = false;
        Window.Query.Clear();
        UpdateResults();
        Rectangle screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Point initial = settings.X.HasValue && settings.Y.HasValue ? new Point(settings.X.Value, settings.Y.Value) : new Point(screen.Left + (screen.Width - Window.Width) / 2, screen.Top + screen.Height / 4);
        Window.Location = TokcatLauncherWindow.Constrain(initial, Window.Size);
        if (Window.Appearance.IsRadial) Window.Radial.ResetAnchor();
        Window.PerformLayout();
        Window.Appearance.Prepare();
        Window.Show(); Window.Activate(); Window.Query.Focus();
        Window.Appearance.Presented();
    }

    void RefreshCatalog()
    {
        if (disposed || scanning) return;
        scanning = true;
        // AppsFolder automation is isolated on an STA worker, away from metric refreshes.
        var thread = new Thread(delegate()
        {
            TokcatLauncherIndex next = null;
            string error = null;
            try { next = new TokcatLauncherIndex(TokcatLauncherCatalog.Scan()); }
            catch (Exception failure) { error = failure.Message; }
            if (disposed) return;
            try
            {
                Window.BeginInvoke((Action)delegate
                {
                    if (disposed) return;
                    scanning = false;
                    if (next != null) index = next;
                    catalogError = error == null ? null : "应用列表读取失败 · " + error;
                    UpdateResults();
                });
            }
            catch (InvalidOperationException) { }
        });
        thread.IsBackground = true; thread.SetApartmentState(ApartmentState.STA); thread.Start();
    }

    void Recall(bool older)
    {
        int next = historyCursor + (older ? 1 : -1);
        if (next < -1 || next >= settings.History.Count) return;
        historyCursor = next;
        recalling = true;
        try
        {
            Window.BrowsingHistory = next >= 0;
            string text = next < 0 ? "" : settings.History[next].Text;
            if (Window.Query.Text == text) UpdateResults();
            else Window.Query.Text = text;
            Window.Query.SelectionStart = Window.Query.TextLength;
        }
        finally { recalling = false; }
    }

    void ClearFileQuery()
    {
        fileDebounce.Stop(); fileSearch.Cancel();
        pendingFileQuery = null; completedFileQuery = null; fileError = null;
        fileResults = new TokcatEverythingFile[0];
    }

    void InputChanged()
    {
        // The native TextBox.Text does not include the IME's in-progress
        // spelling/candidate. Search the same composed string that is drawn.
        string text = Window.Query.DisplayText;
        if (observedInput == text) return;
        observedInput = text;
        if (!recalling) { historyCursor = -1; Window.BrowsingHistory = false; }
        UpdateResults();
    }

    void UpdateResults()
    {
        if (disposed) return;
        string text = Window.Query.DisplayText.Trim();
        if (!Window.Visible && text.Length > 0) return;
        string hint = "已索引 " + index.Count + " 个应用 · ↑ 历史 · Enter 执行 · Ctrl+Enter 文件位置";
        if (text.Length == 0)
        {
            Window.RadialSearchResults = new TokcatLauncherResult[0];
            ClearDictionaryQuery();
            ClearFileQuery();
            if (scanning) hint = "正在读取应用列表…";
            else if (catalogError != null) hint = catalogError;
            Window.SetResults(Window.Appearance.IsRadial ? new TokcatLauncherResult[0] : TokcatLauncherRanking.History(settings), hint);
            return;
        }
        var translation = TokcatLauncherTranslationInput.Parse(text);
        if (translation != null)
        {
            ClearFileQuery();
            UpdateTranslation(translation);
            return;
        }
        if (Window.Appearance.IsRadial && requestedTranslation == text)
        {
            ClearFileQuery(); UpdateTranslation(TokcatLauncherTranslationInput.Parse("tran+" + text)); return;
        }
        ClearDictionaryQuery();
        if (pendingFileQuery != text)
        {
            ClearFileQuery(); pendingFileQuery = text; fileDebounce.Start();
        }
        bool filesReady = completedFileQuery == text;
        if (!filesReady) hint += " · 文件搜索中…";
        else if (fileError != null) hint = fileError;
        else hint += " · Everything";
        var recalled = historyCursor >= 0 && historyCursor < settings.History.Count ? settings.History[historyCursor] : null;
        var results = TokcatLauncherRanking.Build(text, settings, index.SearchMatches(text, 200),
            filesReady ? fileResults : new TokcatEverythingFile[0], filesReady && !scanning, recalled);
        if (results.Length == 0)
        {
            var calculation = TokcatLauncherCalculator.Evaluate(text);
            if (calculation != null && calculation.Error != null) hint = calculation.Error;
            else if (catalogError != null) hint = catalogError;
        }
        if (Window.Appearance.IsRadial)
        {
            var direct = TokcatLauncherTranslationInput.Parse("tran+" + text);
            bool allowsTranslation = direct.IsDictionaryCandidate && TokcatLauncherCalculator.Evaluate(text) == null &&
                !results.Any(r => r.Kind == "settings" || (r.Kind == "terminal" && r.Score >= 1400) || (r.Kind == "website" && (r.Key.StartsWith("url:") || r.Score >= 1400)));
            if (allowsTranslation) results = results.Where(r => !r.Key.StartsWith("search:")).Concat(new[] { TranslationChoice() }).ToArray();
        }
        PublishResults(results, hint);
    }

    static TokcatLauncherResult TranslationChoice()
    {
        return new TokcatLauncherResult { Title = "翻译", Detail = "查看单词释义", Kind = "translate", Key = "translate", RadialWeight = 1.8 };
    }

    void PublishResults(IEnumerable<TokcatLauncherResult> results, string hint)
    {
        if (!Window.Appearance.IsRadial) { Window.SetResults(results, hint); return; }
        string query = Window.Query.DisplayText.Trim();
        var translation = TokcatLauncherTranslationInput.Parse(query);
        string content = translation == null ? query : translation.Text;
        var engine = settings.DefaultSearch;
        string searchUrl = (engine == null ? "https://www.baidu.com/s?wd={query}" : engine.Value).Replace("{query}", Uri.EscapeDataString(content));
        Window.RadialSearchResults = query.Length == 0 || content.Length == 0 ? new TokcatLauncherResult[0] : new[] {
            new TokcatLauncherResult { Title = "网页搜索", Detail = engine == null ? "百度搜索" : engine.Name, Kind = "website", Key = "web-search", Value = searchUrl, RadialWeight = 0.25 }
        };
        var primary = results.Where(r => !r.Key.StartsWith("search:") && r.Key != "web-search").ToArray();
        if (query.Equals("setup", StringComparison.OrdinalIgnoreCase)) primary = primary.Where(r => r.Kind == "settings").Take(1).ToArray();
        else if (query.StartsWith(">")) primary = primary.Where(r => r.Kind == "terminal").Take(1).ToArray();
        else if (TokcatLauncherCalculator.Evaluate(query) != null) primary = primary.Where(r => r.Kind == "calculation").Take(1).ToArray();
        else
        {
            var command = settings.Commands.FirstOrDefault(c => c.Enabled && c.Keyword.Equals(query, StringComparison.OrdinalIgnoreCase));
            var web = primary.FirstOrDefault(r => r.Kind == "website" && (r.Key.StartsWith("url:") || r.Score >= 1400));
            if (command != null) primary = primary.Where(r => r.Key == "command:" + command.Keyword).Take(1).ToArray();
            else if (web != null) primary = new[] { web };
        }
        for (int i = 0; i < primary.Length; i++)
        {
            var item = primary[i];
            if (item.Kind == "application" || item.Kind == "translation")
            {
                int count = settings.Usage.Where(u => u.Key == item.Key).Select(u => u.Count).FirstOrDefault();
                item.RadialWeight = 2 / (1 + i * 0.25) + Math.Min(2.4, Math.Log(count + 1, 2) * 0.4);
            }
        }
        Window.Radial.CancelAim();
        Window.SetResults(primary.Concat(Window.RadialSearchResults).OrderByDescending(r => r.RadialWeight), hint);
    }

    void ClearDictionaryQuery()
    {
        dictionaryDebounce.Stop();
        Interlocked.Increment(ref dictionaryGeneration);
        dictionaryQuery = null; dictionaryDefinition = null; dictionaryError = null;
        dictionaryPending = false; prefersWebTranslation = false;
    }

    void UpdateTranslation(TokcatLauncherTranslationInput translation)
    {
        if (Window.Appearance.IsRadial && translation.IsDictionaryCandidate && requestedTranslation != Window.Query.DisplayText.Trim())
        {
            ClearDictionaryQuery(); PublishResults(new[] { TranslationChoice() }, "选择翻译查看释义"); return;
        }
        if (dictionaryQuery != translation.Text)
        {
            ClearDictionaryQuery(); dictionaryQuery = translation.Text;
            if (translation.IsDictionaryCandidate && !string.IsNullOrWhiteSpace(settings.DictionaryPath))
            {
                dictionaryPending = true; dictionaryDebounce.Start();
            }
        }
        if (dictionaryDefinition != null && !prefersWebTranslation) { Window.SetDefinition(dictionaryDefinition); return; }
        var results = dictionaryPending ? new TokcatLauncherResult[0] : settings.RankedTranslations().Select(p => p.Request(translation.Text)).Where(r => r != null).Take(Window.Appearance.IsRadial ? 100 : 5).ToArray();
        string hint = translation.Text.Length == 0 ? "输入 tran+内容 或 tran 内容" : dictionaryPending ? "正在查询本地词典…" :
            dictionaryError ?? (results.Length == 0 ? "没有启用的网页翻译方式，请在启动器设置 → 翻译中添加。" : "翻译 · ↑↓ 选择 · Enter 打开网页 · 默认方式置顶");
        PublishResults(results, hint);
    }

    void LookupDictionary()
    {
        int generation = dictionaryGeneration;
        string text = dictionaryQuery, dictionaryPath = settings.DictionaryPath;
        ThreadPool.QueueUserWorkItem(delegate
        {
            if (generation != Interlocked.CompareExchange(ref dictionaryGeneration, 0, 0)) return;
            string definition = null, error = null;
            try { lock (dictionary) definition = dictionary.Lookup(dictionaryPath, text); }
            catch (Exception failure) { error = "本地词典不可用，已显示网页翻译 · " + failure.Message; }
            if (disposed) return;
            try
            {
                Window.BeginInvoke((Action)delegate
                {
                    if (disposed || generation != dictionaryGeneration || !Window.Visible) return;
                    dictionaryDefinition = definition; dictionaryError = error; dictionaryPending = false;
                    UpdateResults();
                });
            }
            catch (InvalidOperationException) { }
        });
    }

    public void ShowWebTranslations() { prefersWebTranslation = true; UpdateResults(); Window.Query.Focus(); }

    void OpenContainingFolder()
    {
        var result = Window.Results.SelectedItem as TokcatLauncherResult;
        if (result == null) return;
        if (result.Kind != "file") { SubmitSelection(); return; }
        try
        {
            if (result.Value.IndexOf('"') >= 0) throw new InvalidDataException("文件位置无效。");
            Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + result.Value + "\"") { UseShellExecute = true });
            string input = Window.Query.DisplayText.Trim();
            settings.Remember(input.Length == 0 ? result.Input : input, null, result.Kind, result.Value, result.Key);
            Save(); Window.Hide();
        }
        catch (Exception error) { Window.SetHint("无法打开位置 · " + error.Message, true); }
    }

    public void SubmitSelection()
    {
        var radialResult = Window.Results.SelectedItem as TokcatLauncherResult;
        if (Window.Appearance.IsRadial && radialResult != null)
        {
            if (radialResult.Kind == "translate") { requestedTranslation = Window.Query.DisplayText.Trim(); UpdateResults(); Window.Query.Focus(); return; }
            if (radialResult.Kind == "web-translations") { ShowWebTranslations(); return; }
        }
        string definition = Window.DictionaryDefinition;
        if (definition != null && (!Window.Appearance.IsRadial || (radialResult != null && radialResult.Kind == "definition")))
        {
            try
            {
                Clipboard.SetText(definition);
                string text = Window.Query.DisplayText.Trim();
                settings.Remember(text, null, "fill", text, "dictionary:" + dictionaryQuery); Save(); Window.Hide();
            }
            catch (Exception error) { Window.SetHint("无法复制释义 · " + error.Message, true); }
            return;
        }
        var result = Window.Results.SelectedItem as TokcatLauncherResult;
        if (result == null) return;
        string input = Window.Query.DisplayText.Trim();
        if (result.Kind == "fill")
        {
            Window.Query.Text = result.Value;
            Window.Query.SelectionStart = Window.Query.TextLength;
            Window.Query.Focus();
            return;
        }
        if (input.Length == 0) input = result.Input ?? result.Title;
        Window.Hide();
        try
        {
            switch (result.Kind)
            {
                case "application":
                    if (result.App.Packaged)
                    {
                        if (result.App.Target.IndexOf('"') >= 0) throw new InvalidDataException("应用入口无效。");
                        Process.Start(new ProcessStartInfo("explorer.exe", "\"shell:AppsFolder\\" + result.App.Target + "\"") { UseShellExecute = true });
                    }
                    else
                    {
                        if (!File.Exists(result.App.Target)) throw new FileNotFoundException("应用已移动或删除，请重新搜索。");
                        Process.Start(new ProcessStartInfo(result.App.Target) { UseShellExecute = true });
                    }
                    break;
                case "calculation": Clipboard.SetText(result.Value); break;
                case "translation":
                case "website": Process.Start(new ProcessStartInfo(result.Value) { UseShellExecute = true }); break;
                case "file":
                    if (!File.Exists(result.Value) && !Directory.Exists(result.Value)) throw new FileNotFoundException("文件已移动或删除，请重新搜索。");
                    Process.Start(new ProcessStartInfo(result.Value) { UseShellExecute = true });
                    break;
                case "terminal":
                    string executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                    string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(result.Value));
                    Process.Start(new ProcessStartInfo(executable, "-NoLogo -NoExit -EncodedCommand " + encoded) { UseShellExecute = true });
                    break;
                case "settings": if (OpenSettings != null) OpenSettings(this, EventArgs.Empty); break;
            }
            settings.Remember(input, result.App, result.Kind, result.Value, result.Key); Save();
        }
        catch (Exception error)
        {
            Window.Show(); Window.Activate(); Window.Query.Focus();
            Window.SetHint("无法执行 · " + error.Message, true);
        }
    }

    public void Configure(IWin32Window owner)
    {
        if (!configurationValid)
        {
            MessageBox.Show(owner, Status, "tokcat 快速启动设置");
            return;
        }
        hotKey.Unregister();
        try
        {
            using (var dialog = new TokcatLauncherSettingsWindow(settings.Copy(), palette))
            {
                if (dialog.ShowDialog(owner) != DialogResult.OK) return;
                ApplyConfiguration(dialog.Settings, dialog.ClearsHistory);
            }
        }
        catch (Exception error) { MessageBox.Show(owner, error.Message, "无法保存启动器设置"); }
        finally { Register(); }
    }

    void ApplyConfiguration(TokcatLauncherSettings next, bool clearsHistory)
    {
        if (!configurationValid) throw new InvalidDataException(Status);
        next.Validate(); hotKey.Unregister();
        try
        {
            if (next.Enabled && enableHotKey && !hotKey.Register(next.Modifiers, next.Key))
                throw new InvalidDataException("这个快捷键已被占用，请重新录入。");
            next.X = settings.X; next.Y = settings.Y;
            if (!clearsHistory) { next.History = settings.History; next.Usage = settings.Usage; }
            next.Save(path); settings = next;
            ClearDictionaryQuery();
            Window.Appearance.Configure(settings.Skin, settings.AutoTextColor);
            Window.Results.SelectedIndex = -1; UpdateResults();
            if (Window.Visible) { Window.Appearance.Prepare(); Window.Appearance.Presented(); }
        }
        finally { Register(); }
    }

    public TokcatLauncherSettingsPage CreateSettingsPage()
    {
        Func<TokcatLauncherSettings> read = delegate { return settings.Copy(); };
        var page = new TokcatLauncherSettingsPage(palette, delegate {
            return Window.InvokeRequired ? (TokcatLauncherSettings)Window.Invoke(read) : read();
        });
        page.OpenLauncherRequested += delegate {
            if (Window.InvokeRequired) Window.BeginInvoke((Action)Show);
            else Show();
        };
        page.SaveRequested += delegate
        {
            var draft = page.Editor.Settings.Copy();
            bool clear = page.Editor.ClearsHistory;
            Action apply = delegate { ApplyConfiguration(draft, clear); };
            if (Window.InvokeRequired)
            {
                try { Window.Invoke(apply); }
                catch (System.Reflection.TargetInvocationException error)
                { System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error.InnerException).Throw(); }
            }
            else apply();
            page.AcceptSaved();
        };
        if (!configurationValid) page.Enabled = false;
        return page;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        catalogRefresh.Stop(); catalogRefresh.Dispose();
        ClearDictionaryQuery(); dictionaryDebounce.Dispose();
        fileDebounce.Stop(); fileDebounce.Dispose(); fileSearch.Dispose();
        Save(); hotKey.Dispose(); Window.Dispose();
    }
}

// Own the editor, IME, global shortcut, search callbacks and rendering on the
// same STA. Dashboard snapshot processing can then run independently of input.
public sealed class TokcatLauncherHost : IDisposable
{
    readonly Thread thread;
    readonly Control dashboard;
    readonly TokcatLauncherController controller;
    readonly Control dispatcher;
    volatile bool closing;
    public event EventHandler StatusChanged, OpenSettings;
    public string Status { get { return controller.Status; } }

    public TokcatLauncherHost(Control dashboard, string path, Color[] palette, bool enableHotKey)
    {
        this.dashboard = dashboard;
        var dashboardHandle = dashboard.Handle;
        TokcatLauncherController started = null;
        Control dispatch = null;
        Exception failure = null;
        using (var ready = new ManualResetEventSlim(false))
        {
            thread = new Thread(delegate()
            {
                try
                {
                    dispatch = new Control();
                    var dispatchHandle = dispatch.Handle;
                    started = new TokcatLauncherController(path, palette, enableHotKey);
                    var editorHandle = started.Window.Handle;
                    started.StatusChanged += delegate { NotifyDashboard(StatusChanged); };
                    started.OpenSettings += delegate { NotifyDashboard(OpenSettings); };
                }
                catch (Exception error) { failure = error; }
                finally { ready.Set(); }
                try { if (failure == null) Application.Run(); }
                finally
                {
                    if (started != null) started.Dispose();
                    if (dispatch != null) dispatch.Dispose();
                }
            });
            thread.Name = "tokcat launcher input";
            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            ready.Wait();
        }
        if (failure != null) throw new InvalidOperationException("Unable to start the launcher", failure);
        controller = started;
        dispatcher = dispatch;
    }
    void NotifyDashboard(EventHandler handler)
    {
        if (closing || handler == null) return;
        try { dashboard.BeginInvoke((Action)delegate { if (!closing) handler(this, EventArgs.Empty); }); }
        catch (InvalidOperationException) { if (!dashboard.Disposing && !dashboard.IsDisposed && !closing) throw; }
    }
    public void Show() { if (!closing) dispatcher.BeginInvoke((Action)controller.Show); }
    public TokcatLauncherSettingsPage CreateSettingsPage() { return controller.CreateSettingsPage(); }
    public void Dispose()
    {
        if (closing) return;
        closing = true;
        if (thread.IsAlive)
        {
            dispatcher.BeginInvoke((Action)Application.ExitThread);
            thread.Join();
        }
    }
}

public sealed class TokcatLauncherSettingsWindow : Form
{
    public TokcatLauncherSettings Settings { get; private set; }
    public bool ClearsHistory { get; private set; }
    public bool Embedded { get; private set; }
    public string PreviewSkin { get { return skin.SelectedIndex == 2 ? "radial" : skin.SelectedIndex == 1 ? "cyber" : "classic"; } }
    public bool PreviewAutomaticText { get { return automaticText.Checked; } }
    public event EventHandler AppearanceChanged;
    public event EventHandler SaveRequested;
    public event EventHandler DiscardRequested;
    public readonly Button SaveSettings = new Button { Text = "保存", Size = new Size(90, 30) };
    public readonly Button CancelSettings = new Button { Text = "取消", DialogResult = DialogResult.Cancel, Size = new Size(90, 30) };
    public readonly TabControl Tabs = new TabControl { Dock = DockStyle.Fill };
    readonly CheckBox enabled = new CheckBox();
    readonly TextBox shortcut = new TextBox();
    readonly DataGridView commands = new DataGridView(), websites = new DataGridView();
    readonly DataGridView translations = new DataGridView();
    readonly ComboBox skin = new ComboBox(), searchEngine = new ComboBox();
    readonly CheckBox automaticText = new CheckBox();
    readonly TextBox dictionaryPath = new TextBox();
    int modifiers, key;

    sealed class SearchChoice
    {
        public string Keyword, Name;
        public override string ToString() { return Name; }
    }

    public TokcatLauncherSettingsWindow(TokcatLauncherSettings settings, Color[] palette)
    {
        Settings = settings; modifiers = settings.Modifiers; key = settings.Key;
        Text = "tokcat · 快速启动设置";
        AutoScaleDimensions = new SizeF(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Microsoft YaHei UI", 9);
        ClientSize = new Size(760, 490); MinimumSize = new Size(650, 420);
        BackColor = palette[0]; ForeColor = palette[2]; StartPosition = FormStartPosition.CenterParent;
        var tabs = Tabs;
        var general = new TabPage("通用") { BackColor = palette[1], ForeColor = palette[2], Padding = new Padding(24), AutoScroll = true };
        enabled.Text = "启用全局快捷键"; enabled.Checked = settings.Enabled; enabled.SetBounds(24, 108, 300, 30);
        var caption = new Label { Text = "点击下方输入框，按下新的组合键", AutoSize = true, Location = new Point(24, 150) };
        shortcut.ReadOnly = true; shortcut.Text = TokcatLauncherController.FormatShortcut(modifiers, key); shortcut.SetBounds(24, 178, 350, 30);
        shortcut.AccessibleName = "录入快速启动快捷键";
        shortcut.KeyDown += delegate(object sender, KeyEventArgs e)
        {
            e.SuppressKeyPress = true;
            if (e.KeyCode == Keys.ControlKey || e.KeyCode == Keys.ShiftKey || e.KeyCode == Keys.Menu) return;
            if (!e.Control && !e.Alt) return;
            modifiers = (e.Alt ? 1 : 0) | (e.Control ? 2 : 0) | (e.Shift ? 4 : 0); key = (int)e.KeyCode;
            shortcut.Text = TokcatLauncherController.FormatShortcut(modifiers, key);
        };
        var skinCaption = new Label { Text = "启动器皮肤", Location = new Point(24, 26), AutoSize = true };
        skin.DropDownStyle = ComboBoxStyle.DropDownList; skin.Items.AddRange(new object[] { "经典", "赛博悬浮", "赛博轮盘" });
        skin.SelectedIndex = settings.Skin == "radial" ? 2 : settings.Skin == "cyber" ? 1 : 0; skin.SetBounds(150, 22, 224, 30); skin.AccessibleName = "启动器皮肤";
        automaticText.Text = "赛博皮肤：根据背景自动调整字色（仅打开时在内存采样）";
        automaticText.Checked = settings.AutoTextColor; automaticText.SetBounds(24, 66, 660, 30);
        skin.SelectedIndexChanged += delegate { if (AppearanceChanged != null) AppearanceChanged(this, EventArgs.Empty); };
        automaticText.CheckedChanged += delegate { if (AppearanceChanged != null) AppearanceChanged(this, EventArgs.Empty); };
        var hint = new Label { Text = "运行 Everything 后可搜索文件，Ctrl+Enter 打开所在位置\n中文输入法组字即时匹配；tran+翻译，>命令，setup 打开设置\n按 ↑ 调出历史；经典／赛博悬浮可拖动背景保存位置\n轮盘最多三层，跟随鼠标；方向键固定，悬停、点击或回车选择\n按住 Ctrl 指向，松开执行；Ctrl+滚轮阅读释义；Esc 收起", Location = new Point(24, 246), Size = new Size(650, 108) };
        var clear = new Button { Text = "清空历史与使用权重", Location = new Point(24, 360), Size = new Size(200, 32) };
        clear.Click += delegate { settings.History.Clear(); settings.Usage.Clear(); ClearsHistory = true; clear.Text = "保存后清空历史与权重"; };
        general.Controls.AddRange(new Control[] { enabled, caption, shortcut, skinCaption, skin, automaticText, hint, clear });
        tabs.TabPages.Add(general);
        tabs.TabPages.Add(BuildEntries("命令", commands, settings.Commands, "PowerShell 命令"));
        var webPage = BuildEntries("网站", websites, settings.Websites, "网址，搜索词使用 {query}");
        var searchPanel = new Panel { Dock = DockStyle.Top, Height = 48 };
        searchPanel.Controls.Add(new Label { Text = "无匹配时搜索", Location = new Point(12, 15), AutoSize = true });
        searchEngine.DropDownStyle = ComboBoxStyle.DropDownList; searchEngine.SetBounds(140, 10, 240, 30); searchEngine.AccessibleName = "备用搜索引擎";
        searchPanel.Controls.Add(searchEngine); webPage.Controls.Add(searchPanel);
        webPage.Enter += delegate { RefreshSearchChoices(); };
        RefreshSearchChoices();
        tabs.TabPages.Add(webPage);
        tabs.TabPages.Add(BuildTranslations(settings));
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 52, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
        var cancel = CancelSettings;
        var save = SaveSettings;
        cancel.Click += delegate { if (Embedded && DiscardRequested != null) DiscardRequested(this, EventArgs.Empty); };
        save.Click += delegate
        {
            try
            {
                settings.Enabled = enabled.Checked; settings.Modifiers = modifiers; settings.Key = key;
                settings.Skin = PreviewSkin; settings.AutoTextColor = automaticText.Checked;
                var selectedSearch = searchEngine.SelectedItem as SearchChoice;
                settings.PreferredSearchKeyword = selectedSearch == null ? null : selectedSearch.Keyword;
                settings.DictionaryPath = dictionaryPath.Text.Trim(); settings.Translations = ReadTranslations();
                settings.Commands = ReadEntries(commands); settings.Websites = ReadEntries(websites); settings.Validate();
                if (Embedded) { if (SaveRequested != null) SaveRequested(this, EventArgs.Empty); }
                else DialogResult = DialogResult.OK;
            }
            catch (Exception error) { MessageBox.Show(this, error.Message, "请检查启动器设置"); }
        };
        buttons.Controls.AddRange(new Control[] { cancel, save });
        Controls.Add(tabs); Controls.Add(buttons); CancelButton = cancel;
        StyleSettings(this, palette);
        tabs.DrawMode = TabDrawMode.OwnerDrawFixed;
        tabs.DrawItem += delegate(object sender, DrawItemEventArgs e)
        {
            using (var brush = new SolidBrush(e.Index == tabs.SelectedIndex ? palette[1] : palette[0])) e.Graphics.FillRectangle(brush, e.Bounds);
            TextRenderer.DrawText(e.Graphics, tabs.TabPages[e.Index].Text, Font, e.Bounds, palette[2], TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        };
    }

    public void EmbedIn(Control parent)
    {
        Embedded = true; TopLevel = false; FormBorderStyle = FormBorderStyle.None;
        MinimumSize = Size.Empty; Dock = DockStyle.Fill;
        CancelSettings.DialogResult = DialogResult.None;
        parent.Controls.Add(this); Show();
    }

    static void StyleSettings(Control control, Color[] palette)
    {
        control.ForeColor = palette[2]; control.BackColor = control is Form || control is FlowLayoutPanel ? palette[0] : palette[1];
        var grid = control as DataGridView;
        if (grid != null)
        {
            grid.BackgroundColor = palette[1]; grid.GridColor = palette[0]; grid.BorderStyle = BorderStyle.None;
            grid.EnableHeadersVisualStyles = false;
            grid.DefaultCellStyle.BackColor = palette[1]; grid.DefaultCellStyle.ForeColor = palette[2];
            grid.DefaultCellStyle.SelectionBackColor = palette[4]; grid.DefaultCellStyle.SelectionForeColor = palette[2];
            grid.ColumnHeadersDefaultCellStyle.BackColor = palette[0]; grid.ColumnHeadersDefaultCellStyle.ForeColor = palette[3];
            return;
        }
        var button = control as Button;
        if (button != null)
        {
            button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderColor = palette[3];
            button.FlatAppearance.MouseOverBackColor = palette[4];
        }
        var combo = control as ComboBox; if (combo != null) combo.FlatStyle = FlatStyle.Flat;
        foreach (Control child in control.Controls) StyleSettings(child, palette);
    }

    void RefreshSearchChoices()
    {
        var selected = searchEngine.SelectedItem as SearchChoice;
        string keyword = selected == null ? Settings.PreferredSearchKeyword : selected.Keyword;
        searchEngine.Items.Clear();
        foreach (var website in ReadEntries(websites).Where(w => w.Enabled && w.Value.Contains("{query}") && TokcatLauncherResolver.HttpUrl(w.Value.Replace("{query}", "test"), false) != null))
            searchEngine.Items.Add(new SearchChoice { Keyword = website.Keyword, Name = string.IsNullOrWhiteSpace(website.Name) ? website.Keyword : website.Name });
        if (searchEngine.Items.Count == 0) searchEngine.Items.Add(new SearchChoice { Name = "无可用搜索引擎" });
        searchEngine.SelectedIndex = 0;
        for (int i = 0; i < searchEngine.Items.Count; i++)
            if (string.Equals(((SearchChoice)searchEngine.Items[i]).Keyword, keyword ?? "baidu", StringComparison.OrdinalIgnoreCase)) searchEngine.SelectedIndex = i;
    }

    TabPage BuildTranslations(TokcatLauncherSettings settings)
    {
        var page = new TabPage("翻译");
        var help = new Label { Dock = DockStyle.Top, Height = 64, Padding = new Padding(10), Text = "输入 tran+内容 或 tran 内容。默认方式始终置顶，其余方式按使用次数排序。\n地址必须包含 {query}；预设译为中文，可编辑地址更改目标语言。" };
        translations.Dock = DockStyle.Fill; translations.RowHeadersVisible = false; translations.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        translations.Columns.Add(new DataGridViewCheckBoxColumn { Name = "Default", HeaderText = "默认", FillWeight = 35 });
        translations.Columns.Add(new DataGridViewCheckBoxColumn { Name = "Enabled", HeaderText = "启用", FillWeight = 35 });
        translations.Columns.Add("Name", "名称"); translations.Columns.Add("UrlTemplate", "翻译地址（{query} 为内容）"); translations.Columns[3].FillWeight = 280;
        foreach (var provider in settings.Translations)
        {
            int row = translations.Rows.Add(provider.Id == settings.DefaultTranslationId, provider.Enabled, provider.Name, provider.UrlTemplate);
            translations.Rows[row].Tag = provider.Id;
        }
        translations.DefaultValuesNeeded += delegate(object sender, DataGridViewRowEventArgs e) { e.Row.Cells[1].Value = true; e.Row.Tag = Guid.NewGuid().ToString("D"); };
        translations.CurrentCellDirtyStateChanged += delegate { if (translations.IsCurrentCellDirty && translations.CurrentCell.ColumnIndex < 2) translations.CommitEdit(DataGridViewDataErrorContexts.Commit); };
        translations.CellValueChanged += delegate(object sender, DataGridViewCellEventArgs e)
        {
            if (e.RowIndex < 0 || e.ColumnIndex != 0 || !Convert.ToBoolean(translations.Rows[e.RowIndex].Cells[0].Value ?? false)) return;
            foreach (DataGridViewRow row in translations.Rows) if (row.Index != e.RowIndex && !row.IsNewRow) row.Cells[0].Value = false;
        };
        var local = new Panel { Dock = DockStyle.Bottom, Height = 102 };
        local.Controls.Add(new Label { Text = "可选本地词典（UTF-8 JSON：单词 → 释义，最多 8 MiB）", Location = new Point(12, 10), AutoSize = true });
        dictionaryPath.Text = settings.DictionaryPath ?? ""; dictionaryPath.SetBounds(12, 36, 570, 28); dictionaryPath.AccessibleName = "本地词典路径";
        var browse = new Button { Text = "选择…", Location = new Point(600, 34), Size = new Size(90, 30) };
        local.Layout += delegate { dictionaryPath.Width = Math.Max(80, local.ClientSize.Width - 126); browse.Left = local.ClientSize.Width - 102; };
        browse.Click += delegate
        {
            using (var dialog = new OpenFileDialog { Filter = "JSON 词典 (*.json)|*.json", CheckFileExists = true })
                if (dialog.ShowDialog(this) == DialogResult.OK) dictionaryPath.Text = dialog.FileName;
        };
        local.Controls.AddRange(new Control[] { dictionaryPath, browse, new Label { Text = "单词精确命中时显示可滚动释义，回车复制；未配置或未命中时显示网页翻译。", Location = new Point(12, 74), AutoSize = true } });
        page.Controls.Add(translations); page.Controls.Add(help); page.Controls.Add(local);
        return page;
    }

    List<TokcatLauncherTranslationProvider> ReadTranslations()
    {
        translations.EndEdit();
        var entries = new List<TokcatLauncherTranslationProvider>();
        string preferred = null;
        foreach (DataGridViewRow row in translations.Rows)
        {
            if (row.IsNewRow) continue;
            if (row.Tag == null) row.Tag = Guid.NewGuid().ToString("D");
            var provider = new TokcatLauncherTranslationProvider { Id = (string)row.Tag, Enabled = Convert.ToBoolean(row.Cells[1].Value ?? true),
                Name = Convert.ToString(row.Cells[2].Value).Trim(), UrlTemplate = Convert.ToString(row.Cells[3].Value).Trim() };
            entries.Add(provider);
            if (Convert.ToBoolean(row.Cells[0].Value ?? false)) preferred = provider.Id;
        }
        Settings.DefaultTranslationId = preferred;
        return entries;
    }

    static TabPage BuildEntries(string title, DataGridView grid, IEnumerable<TokcatLauncherShortcut> entries, string valueCaption)
    {
        var page = new TabPage(title);
        grid.Dock = DockStyle.Fill; grid.RowHeadersVisible = false;
        grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
        grid.Columns.Add(new DataGridViewCheckBoxColumn { Name = "Enabled", HeaderText = "启用", FillWeight = 35 });
        grid.Columns.Add("Keyword", "关键词"); grid.Columns.Add("Name", "名称"); grid.Columns.Add("Value", valueCaption);
        grid.Columns[3].FillWeight = 260;
        grid.DefaultValuesNeeded += delegate(object sender, DataGridViewRowEventArgs e) { e.Row.Cells[0].Value = true; };
        foreach (var entry in entries) grid.Rows.Add(entry.Enabled, entry.Keyword, entry.Name, entry.Value);
        var help = new Label { Text = "在末行添加条目；选中整行按 Delete 删除。关键词需唯一，填写后点击保存。", Dock = DockStyle.Bottom, Height = 36, Padding = new Padding(8) };
        page.Controls.Add(grid); page.Controls.Add(help);
        return page;
    }
    static List<TokcatLauncherShortcut> ReadEntries(DataGridView grid)
    {
        grid.EndEdit();
        return grid.Rows.Cast<DataGridViewRow>().Where(row => !row.IsNewRow).Select(row => new TokcatLauncherShortcut
        {
            Enabled = Convert.ToBoolean(row.Cells[0].Value ?? true), Keyword = Convert.ToString(row.Cells[1].Value).Trim(),
            Name = Convert.ToString(row.Cells[2].Value).Trim(), Value = Convert.ToString(row.Cells[3].Value).Trim()
        }).ToList();
    }
}
