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
    public readonly TextBox Query = new TextBox();
    public readonly ListBox Results = new ListBox();
    public readonly Label Hint = new Label();
    public event EventHandler Submitted;
    public event EventHandler ContainingFolderRequested;
    public event EventHandler HistoryOlder;
    public event EventHandler HistoryNewer;
    public event EventHandler PositionChanged;
    readonly Panel input = new Panel();
    readonly Color selection;
    bool adjusting;

    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr handle, int message, IntPtr parameter, IntPtr data);

    public TokcatLauncherWindow(Color[] palette)
    {
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
        ClientSize = new Size(640, 94);
        Padding = new Padding(1);
        input.Dock = DockStyle.Top; input.Height = 60; input.BackColor = palette[1];
        var icon = new Label { Text = "⌕", Font = new Font("Segoe UI", 24), ForeColor = palette[3], TextAlign = ContentAlignment.MiddleCenter, Dock = DockStyle.Left, Width = 48 };
        icon.AccessibleName = "拖动以移动快速启动框";
        icon.MouseDown += delegate(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            ReleaseCapture(); SendMessage(Handle, 0x00A1, new IntPtr(2), IntPtr.Zero);
        };
        Query.BorderStyle = BorderStyle.None;
        Query.MaxLength = 8192;
        Query.Font = new Font("Microsoft YaHei UI", 18);
        Query.BackColor = palette[1]; Query.ForeColor = palette[2];
        Query.AccessibleName = "搜索应用、文件、算式、网站或命令";
        Query.SetBounds(54, 15, 562, 32); Query.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right;
        input.Controls.Add(Query); input.Controls.Add(icon);
        Hint.Dock = DockStyle.Bottom; Hint.Height = 32; Hint.Padding = new Padding(12, 6, 0, 0);
        Hint.Font = new Font("Microsoft YaHei UI", 9); Hint.ForeColor = palette[3];
        Results.Dock = DockStyle.Fill; Results.BorderStyle = BorderStyle.None;
        Results.BackColor = palette[1]; Results.ForeColor = palette[2];
        Results.DrawMode = DrawMode.OwnerDrawFixed; Results.ItemHeight = 48;
        Results.AccessibleName = "快速启动搜索结果";
        Results.DrawItem += DrawResult;
        Results.DoubleClick += delegate { Submit(); };
        Controls.Add(Results); Controls.Add(Hint); Controls.Add(input);
        KeyDown += QueryKeyDown;
        Deactivate += delegate { Hide(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); }
        };
        Move += delegate { if (Visible && !adjusting && PositionChanged != null) PositionChanged(this, EventArgs.Empty); };
    }

    void QueryKeyDown(object sender, KeyEventArgs e)
    {
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
        using (var brush = new SolidBrush((e.State & DrawItemState.Selected) != 0 ? selection : Results.BackColor)) e.Graphics.FillRectangle(brush, e.Bounds);
        var flags = TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine;
        TextRenderer.DrawText(e.Graphics, result.Title, Font, new Rectangle(14, e.Bounds.Top + 4, e.Bounds.Width - 28, 24), ForeColor, flags);
        using (var detailFont = new Font(Font.FontFamily, 9))
            TextRenderer.DrawText(e.Graphics, result.Detail, detailFont, new Rectangle(14, e.Bounds.Top + 28, e.Bounds.Width - 28, 18), Hint.ForeColor, flags);
    }

    string displayedQuery;
    public void SetResults(IEnumerable<TokcatLauncherResult> results, string hint)
    {
        var selected = Results.SelectedItem as TokcatLauncherResult;
        string selectedKey = displayedQuery == Query.Text && selected != null ? selected.Key : null;
        displayedQuery = Query.Text;
        Results.BeginUpdate();
        try
        {
            Results.Items.Clear();
            foreach (var result in results) Results.Items.Add(result);
            if (Results.Items.Count > 0) Results.SelectedIndex = 0;
            if (selectedKey != null)
                for (int i = 0; i < Results.Items.Count; i++)
                    if (string.Equals(((TokcatLauncherResult)Results.Items[i]).Key, selectedKey, StringComparison.OrdinalIgnoreCase)) { Results.SelectedIndex = i; break; }
        }
        finally { Results.EndUpdate(); }
        Hint.Text = hint;
        int wantedHeight = input.Height + Hint.Height + Results.Items.Count * Results.ItemHeight + 2;
        adjusting = true;
        try
        {
            Height = Math.Min(wantedHeight, Screen.FromPoint(Location).WorkingArea.Height);
            Location = Constrain(Location, Size);
        }
        finally { adjusting = false; }
    }

    public static Point Constrain(Point location, Size size)
    {
        Rectangle bounds = Screen.FromPoint(location).WorkingArea;
        return new Point(Math.Max(bounds.Left, Math.Min(location.X, bounds.Right - size.Width)),
            Math.Max(bounds.Top, Math.Min(location.Y, bounds.Bottom - size.Height)));
    }
}

public sealed class TokcatLauncherResult
{
    public string Title, Detail, Kind, Value, Key, Input;
    public double Score;
    public TokcatLauncherApp App;
    public override string ToString() { return Title + " " + Detail; }
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
    readonly System.Windows.Forms.Timer savePosition;
    readonly System.Windows.Forms.Timer fileDebounce = new System.Windows.Forms.Timer { Interval = 180 };
    readonly TokcatEverythingSearch fileSearch;
    TokcatEverythingFile[] fileResults = new TokcatEverythingFile[0];
    string pendingFileQuery, completedFileQuery, fileError;
    TokcatLauncherSettings settings;
    TokcatLauncherIndex index = new TokcatLauncherIndex(new TokcatLauncherApp[0]);
    DateTime lastScan = DateTime.MinValue;
    bool scanning, recalling, configurationValid = true;
    volatile bool disposed;
    int historyCursor = -1;
    string catalogError;
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
        fileSearch = new TokcatEverythingSearch();
        Window.VisibleChanged += delegate { if (!Window.Visible && !disposed) ClearFileQuery(); };
        fileSearch.Completed += delegate(object sender, TokcatEverythingReply reply)
        {
            if (reply.Query != Window.Query.Text.Trim()) return;
            completedFileQuery = reply.Query; fileResults = reply.Files; fileError = reply.Error;
            UpdateResults();
        };
        fileDebounce.Tick += delegate { fileDebounce.Stop(); if (!string.IsNullOrEmpty(pendingFileQuery)) fileSearch.Query(pendingFileQuery); };
        hotKey = new TokcatLauncherHotKey();
        hotKey.Pressed += delegate { if (Window.Visible) Window.Hide(); else Show(); };
        Window.Query.TextChanged += delegate
        {
            if (!recalling) { historyCursor = -1; Window.BrowsingHistory = false; }
            UpdateResults();
        };
        Window.Submitted += delegate { SubmitSelection(); };
        Window.ContainingFolderRequested += delegate { OpenContainingFolder(); };
        Window.HistoryOlder += delegate { Recall(true); };
        Window.HistoryNewer += delegate { Recall(false); };
        savePosition = new System.Windows.Forms.Timer { Interval = 400 };
        savePosition.Tick += delegate { savePosition.Stop(); Save(); };
        Window.PositionChanged += delegate
        {
            settings.X = Window.Left; settings.Y = Window.Top;
            savePosition.Stop(); savePosition.Start();
        };
        Register();
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
        Rectangle screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Point initial = settings.X.HasValue && settings.Y.HasValue ? new Point(settings.X.Value, settings.Y.Value) : new Point(screen.Left + (screen.Width - Window.Width) / 2, screen.Top + screen.Height / 4);
        Window.Location = TokcatLauncherWindow.Constrain(initial, Window.Size);
        Window.Show(); Window.Activate(); Window.Query.Focus();
        RefreshCatalog(); UpdateResults();
    }

    void RefreshCatalog()
    {
        if (scanning || DateTime.UtcNow - lastScan < TimeSpan.FromSeconds(30)) return;
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
                    scanning = false; lastScan = DateTime.UtcNow;
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

    void UpdateResults()
    {
        if (disposed || !Window.Visible) return;
        string text = Window.Query.Text.Trim();
        string hint = "已索引 " + index.Count + " 个应用 · ↑ 历史 · Enter 执行 · Ctrl+Enter 文件位置";
        if (text.Length == 0)
        {
            ClearFileQuery();
            if (scanning) hint = "正在读取应用列表…";
            else if (catalogError != null) hint = catalogError;
            Window.SetResults(TokcatLauncherRanking.History(settings), hint);
            return;
        }
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
        Window.SetResults(results, hint);
    }

    void OpenContainingFolder()
    {
        var result = Window.Results.SelectedItem as TokcatLauncherResult;
        if (result == null) return;
        if (result.Kind != "file") { SubmitSelection(); return; }
        try
        {
            if (result.Value.IndexOf('"') >= 0) throw new InvalidDataException("文件位置无效。");
            Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + result.Value + "\"") { UseShellExecute = true });
            string input = Window.Query.Text.Trim();
            settings.Remember(input.Length == 0 ? result.Input : input, null, result.Kind, result.Value, result.Key);
            Save(); Window.Hide();
        }
        catch (Exception error) { Window.Hint.Text = "无法打开位置 · " + error.Message; }
    }

    public void SubmitSelection()
    {
        var result = Window.Results.SelectedItem as TokcatLauncherResult;
        if (result == null) return;
        string input = Window.Query.Text.Trim();
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
            Window.Hint.Text = "无法执行 · " + error.Message;
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
                var next = dialog.Settings;
                if (next.Enabled && enableHotKey && !hotKey.Register(next.Modifiers, next.Key))
                {
                    MessageBox.Show(owner, "这个快捷键已被占用，请重新录入。", "tokcat 快速启动设置");
                    return;
                }
                next.Save(path); settings = next;
            }
        }
        catch (Exception error) { MessageBox.Show(owner, error.Message, "无法保存启动器设置"); }
        finally { Register(); }
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        fileDebounce.Stop(); fileDebounce.Dispose(); fileSearch.Dispose();
        savePosition.Stop(); savePosition.Dispose();
        Save(); hotKey.Dispose(); Window.Dispose();
    }
}

public sealed class TokcatLauncherSettingsWindow : Form
{
    public TokcatLauncherSettings Settings { get; private set; }
    readonly CheckBox enabled = new CheckBox();
    readonly TextBox shortcut = new TextBox();
    readonly DataGridView commands = new DataGridView(), websites = new DataGridView();
    int modifiers, key;

    public TokcatLauncherSettingsWindow(TokcatLauncherSettings settings, Color[] palette)
    {
        Settings = settings; modifiers = settings.Modifiers; key = settings.Key;
        Text = "tokcat · 快速启动设置";
        Font = new Font("Microsoft YaHei UI", 9);
        ClientSize = new Size(760, 490); MinimumSize = new Size(650, 420);
        BackColor = palette[0]; ForeColor = palette[2]; StartPosition = FormStartPosition.CenterParent;
        var tabs = new TabControl { Dock = DockStyle.Fill };
        var general = new TabPage("通用") { BackColor = palette[1], ForeColor = palette[2], Padding = new Padding(24) };
        enabled.Text = "启用全局快捷键"; enabled.Checked = settings.Enabled; enabled.SetBounds(24, 24, 300, 30);
        var caption = new Label { Text = "点击下方输入框，按下新的组合键", AutoSize = true, Location = new Point(24, 76) };
        shortcut.ReadOnly = true; shortcut.Text = TokcatLauncherController.FormatShortcut(modifiers, key); shortcut.SetBounds(24, 108, 350, 30);
        shortcut.AccessibleName = "录入快速启动快捷键";
        shortcut.KeyDown += delegate(object sender, KeyEventArgs e)
        {
            e.SuppressKeyPress = true;
            if (e.KeyCode == Keys.ControlKey || e.KeyCode == Keys.ShiftKey || e.KeyCode == Keys.Menu) return;
            if (!e.Control && !e.Alt) return;
            modifiers = (e.Alt ? 1 : 0) | (e.Control ? 2 : 0) | (e.Shift ? 4 : 0); key = (int)e.KeyCode;
            shortcut.Text = TokcatLauncherController.FormatShortcut(modifiers, key);
        };
        var hint = new Label { Text = "应用、文件、算式、网站和命令统一匹配，常用项优先\n运行 Everything 后可搜索文件，Ctrl+Enter 打开所在位置\n输入 > 后跟终端命令，setup 打开监控设置\n空白显示历史，按 ↑ 调出最近 50 条输入\n拖动搜索图标可移动启动框，位置自动保存", Location = new Point(24, 168), Size = new Size(650, 130) };
        var clear = new Button { Text = "清空历史与使用权重", Location = new Point(24, 310), Size = new Size(200, 32) };
        clear.Click += delegate { settings.History.Clear(); settings.Usage.Clear(); clear.Text = "保存后清空历史与权重"; };
        general.Controls.AddRange(new Control[] { enabled, caption, shortcut, hint, clear });
        tabs.TabPages.Add(general);
        tabs.TabPages.Add(BuildEntries("命令", commands, settings.Commands, "PowerShell 命令"));
        tabs.TabPages.Add(BuildEntries("网站", websites, settings.Websites, "网址，搜索词使用 {query}"));
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 52, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
        var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, Size = new Size(90, 30) };
        var save = new Button { Text = "保存", Size = new Size(90, 30) };
        save.Click += delegate
        {
            try
            {
                settings.Enabled = enabled.Checked; settings.Modifiers = modifiers; settings.Key = key;
                settings.Commands = ReadEntries(commands); settings.Websites = ReadEntries(websites); settings.Validate();
                DialogResult = DialogResult.OK;
            }
            catch (Exception error) { MessageBox.Show(this, error.Message, "请检查启动器设置"); }
        };
        buttons.Controls.AddRange(new Control[] { cancel, save });
        Controls.Add(tabs); Controls.Add(buttons); CancelButton = cancel;
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
