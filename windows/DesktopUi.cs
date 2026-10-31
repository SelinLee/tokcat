using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Microsoft.Win32;

// Code-only WinForms UI: no web runtime, icon font, or external asset dependency.
// Keep this source compatible with the Windows PowerShell 5.1 C# compiler.
public static class TokcatUi
{
    public static readonly bool Dark = IsDark();
    public static readonly Color Background = Palette("#17151C", "#F6F3EE", SystemColors.Window);
    public static readonly Color Surface = Palette("#25222D", "#FFFFFF", SystemColors.Window);
    public static readonly Color Text = Palette("#F5F2F7", "#1F1A26", SystemColors.WindowText);
    public static readonly Color Secondary = Palette("#BDB5CC", "#544D61", SystemColors.WindowText);
    public static readonly Color Border = Palette("#443E50", "#E2DDE7", SystemColors.WindowFrame);
    public static readonly Color Accent = Palette("#91A9FF", "#4965CC", SystemColors.WindowText);
    public static readonly Color Selection = Palette("#34324B", "#EDF0FF", SystemColors.Control);

    static Color Palette(string dark, string light, Color highContrast)
    {
        return SystemInformation.HighContrast ? highContrast : ColorTranslator.FromHtml(Dark ? dark : light);
    }

    static bool IsDark()
    {
        if (SystemInformation.HighContrast) return false;
        try
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                return key != null && Convert.ToInt32(key.GetValue("AppsUseLightTheme", 1)) == 0;
        }
        catch { return false; }
    }

    public static Color StateColor(string state)
    {
        if (SystemInformation.HighContrast) return SystemColors.WindowText;
        switch (state)
        {
            case "running": return ColorTranslator.FromHtml(Dark ? "#E8B857" : "#966300");
            case "waiting": case "approval": return ColorTranslator.FromHtml(Dark ? "#F2A478" : "#B45422");
            case "failed": case "stalled": return ColorTranslator.FromHtml(Dark ? "#F18E95" : "#BB384A");
            case "completed": return ColorTranslator.FromHtml(Dark ? "#83C7A1" : "#237447");
            default: return Secondary;
        }
    }

    public static void StyleWindow(Form form)
    {
        form.AutoScaleDimensions = new SizeF(96, 96);
        form.AutoScaleMode = AutoScaleMode.Dpi;
        form.BackColor = Background; form.ForeColor = Text;
        form.Font = new Font("Microsoft YaHei UI", 9F);
    }

    public static Label Label(string text, float size, Color color)
    {
        return new Label { Text = text, AutoSize = false, ForeColor = color,
            Font = new Font("Microsoft YaHei UI", size), BackColor = Color.Transparent };
    }

    public static Button Button(string text, string icon, bool primary)
    {
        Button button = new Button { Text = text, Height = 34, Width = 128, FlatStyle = FlatStyle.Flat,
            BackColor = primary ? Selection : Surface, ForeColor = primary ? Accent : Text,
            TextImageRelation = TextImageRelation.ImageBeforeText, ImageAlign = ContentAlignment.MiddleCenter,
            Cursor = Cursors.Hand, AccessibleName = text, Margin = new Padding(0, 0, 8, 0) };
        button.FlatAppearance.BorderColor = Border;
        button.FlatAppearance.MouseOverBackColor = Selection;
        Image image = Icon(icon, primary ? Accent : Secondary, 18);
        button.Image = image;
        button.Disposed += delegate { image.Dispose(); };
        return button;
    }

    public static void StyleList(ListView list)
    {
        list.View = View.Details; list.FullRowSelect = true; list.HideSelection = false;
        list.GridLines = false; list.BorderStyle = BorderStyle.None;
        list.BackColor = Surface; list.ForeColor = Text;
        list.Font = new Font("Microsoft YaHei UI", 9F);
        list.AccessibleName = "任务或用量明细";
        // The image list also provides comfortable row spacing at the current DPI.
        ImageList images = new ImageList { ImageSize = new Size(20, 28), ColorDepth = ColorDepth.Depth32Bit };
        foreach (string state in new[] { "running", "waiting", "approval", "completed", "failed", "stalled", "interrupted", "unknown" })
        {
            using (Bitmap bitmap = new Bitmap(20, 28))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            using (Bitmap glyph = Icon(state, StateColor(state), 18))
            {
                graphics.DrawImageUnscaled(glyph, 1, 5); images.Images.Add(state, bitmap);
            }
        }
        list.SmallImageList = images;
        list.Disposed += delegate { images.Dispose(); };
        list.OwnerDraw = true;
        list.DrawColumnHeader += delegate(object sender, DrawListViewColumnHeaderEventArgs e) {
            using (SolidBrush brush = new SolidBrush(Background)) e.Graphics.FillRectangle(brush, e.Bounds);
            using (Pen pen = new Pen(Border)) e.Graphics.DrawLine(pen, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            Rectangle bounds = Rectangle.Inflate(e.Bounds, -8, 0);
            TextRenderer.DrawText(e.Graphics, e.Header.Text, list.Font, bounds, Secondary,
                TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
        };
        list.DrawSubItem += delegate(object sender, DrawListViewSubItemEventArgs e) {
            Color background = e.Item.Selected ? Selection : Surface;
            using (SolidBrush brush = new SolidBrush(background)) e.Graphics.FillRectangle(brush, e.Bounds);
            Rectangle bounds = Rectangle.Inflate(e.Bounds, -8, 0);
            if (e.ColumnIndex == 0 && !String.IsNullOrEmpty(e.Item.ImageKey))
            {
                Image glyph = images.Images[e.Item.ImageKey];
                if (glyph != null) e.Graphics.DrawImageUnscaled(glyph, bounds.Left, bounds.Top + (bounds.Height - glyph.Height) / 2);
                bounds.X += 24; bounds.Width -= 24;
            }
            TextFormatFlags align = e.Header.TextAlign == HorizontalAlignment.Right ? TextFormatFlags.Right : TextFormatFlags.Left;
            TextRenderer.DrawText(e.Graphics, e.SubItem.Text, list.Font, bounds, Text,
                align | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
        };
    }

    public static void StyleToolbar(Control toolbar)
    {
        toolbar.BackColor = Background; toolbar.Padding = new Padding(12, 8, 12, 8);
        foreach (Control control in toolbar.Controls)
        {
            control.ForeColor = Text;
            if (control is ComboBox) control.BackColor = Surface;
            Button button = control as Button;
            if (button == null) continue;
            button.FlatStyle = FlatStyle.Flat; button.BackColor = Surface;
            button.FlatAppearance.BorderColor = Border; button.Height = 32;
            button.AccessibleName = button.Text;
        }
    }

    public static Bitmap Icon(string name, Color color, int size)
    {
        Bitmap bitmap = new Bitmap(size, size);
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Pen p = new Pen(color, 1.6F))
        using (SolidBrush brush = new SolidBrush(color))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.ScaleTransform(size / 24F, size / 24F);
            p.StartCap = p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
            switch (name)
            {
                case "cat":
                    g.DrawPolygon(p, new[] { new PointF(4, 12), new PointF(4, 4), new PointF(9, 7), new PointF(15, 7), new PointF(20, 4), new PointF(20, 12), new PointF(19, 18), new PointF(15, 21), new PointF(9, 21), new PointF(5, 18) });
                    g.FillEllipse(brush, 8, 12, 2, 2); g.FillEllipse(brush, 14, 12, 2, 2);
                    g.DrawLine(p, 10, 17, 14, 17); break;
                case "tasks":
                    g.DrawRectangle(p, 4, 4, 16, 16); g.DrawLine(p, 8, 9, 16, 9); g.DrawLine(p, 8, 14, 14, 14); break;
                case "usage":
                    g.DrawLine(p, 5, 20, 20, 20); g.DrawLine(p, 6, 16, 6, 11); g.DrawLine(p, 12, 16, 12, 5); g.DrawLine(p, 18, 16, 18, 8); break;
                case "settings":
                    g.DrawEllipse(p, 7, 7, 10, 10); g.DrawEllipse(p, 10, 10, 4, 4);
                    for (int i = 0; i < 8; i++) { double a = i * Math.PI / 4; g.DrawLine(p, 12 + (float)Math.Cos(a) * 7, 12 + (float)Math.Sin(a) * 7, 12 + (float)Math.Cos(a) * 9, 12 + (float)Math.Sin(a) * 9); } break;
                case "refresh":
                    g.DrawArc(p, 5, 5, 14, 14, 45, 290); g.DrawLines(p, new[] { new Point(19, 4), new Point(19, 10), new Point(13, 10) }); break;
                case "folder":
                    g.DrawPolygon(p, new[] { new Point(3, 7), new Point(9, 7), new Point(11, 9), new Point(21, 9), new Point(21, 19), new Point(3, 19) }); break;
                case "conversation":
                    g.DrawPolygon(p, new[] { new Point(4, 4), new Point(20, 4), new Point(20, 16), new Point(10, 16), new Point(5, 20), new Point(5, 16), new Point(4, 16) });
                    g.DrawLine(p, 8, 9, 16, 9); break;
                case "record":
                    g.DrawRectangle(p, 6, 3, 12, 18); g.DrawLine(p, 9, 8, 15, 8); g.DrawLine(p, 9, 12, 15, 12); g.DrawLine(p, 9, 16, 13, 16); break;
                case "taskbar":
                    g.DrawRectangle(p, 3, 5, 18, 15); g.DrawLine(p, 3, 16, 21, 16); g.DrawLine(p, 7, 18, 11, 18); break;
                case "exit":
                    g.DrawArc(p, 5, 5, 14, 15, -55, 290); g.DrawLine(p, 12, 3, 12, 11); break;
                case "completed": case "read":
                    g.DrawEllipse(p, 3, 3, 18, 18); g.DrawLines(p, new[] { new Point(7, 12), new Point(10, 15), new Point(17, 8) }); break;
                case "failed":
                    g.DrawEllipse(p, 3, 3, 18, 18); g.DrawLine(p, 8, 8, 16, 16); g.DrawLine(p, 16, 8, 8, 16); break;
                case "waiting": case "approval":
                    g.DrawEllipse(p, 3, 3, 18, 18); g.DrawLine(p, 12, 7, 12, 13); g.FillEllipse(brush, 11, 16, 2, 2); break;
                case "running": g.DrawArc(p, 4, 4, 16, 16, -75, 290); g.FillEllipse(brush, 16, 3, 4, 4); break;
                case "stalled":
                    g.DrawEllipse(p, 3, 3, 18, 18); g.DrawLine(p, 10, 8, 10, 16); g.DrawLine(p, 14, 8, 14, 16); break;
                default: g.DrawEllipse(p, 5, 5, 14, 14); g.FillEllipse(brush, 11, 11, 2, 2); break;
            }
        }
        return bitmap;
    }
}

public sealed class TokcatSessionList : ListView
{
    public TokcatSessionList() { DoubleBuffered = true; }
}

public sealed class TokcatMainWindow : Form
{
    public readonly ListView Sessions = new TokcatSessionList();
    public readonly Label Note = TokcatUi.Label("正在读取本地任务…", 9, TokcatUi.Secondary);
    public readonly Label Quota = TokcatUi.Label("Codex 本地额度：等待记录", 9, TokcatUi.Secondary);
    public readonly TextBox Search = new TextBox();
    public readonly ComboBox SourceFilter = new ComboBox();
    public readonly ComboBox StateFilter = new ComboBox();
    public readonly Button UsageButton = TokcatUi.Button("用量统计", "usage", false);
    public readonly Button StripButton = TokcatUi.Button("隐藏任务栏", "taskbar", false);
    public readonly Button QuitButton = TokcatUi.Button("退出 tokcat", "exit", false);
    public readonly Button RefreshButton = TokcatUi.Button("立即刷新", "refresh", false);
    public readonly Button ConversationButton = TokcatUi.Button("阅读对话", "conversation", true);
    public readonly Button ProjectButton = TokcatUi.Button("打开项目", "folder", false);
    public readonly Button RecordButton = TokcatUi.Button("原始记录", "record", false);
    public readonly Button ReadButton = TokcatUi.Button("标记已读", "read", false);
    public readonly CheckBox Cpu = new CheckBox(), Gpu = new CheckBox(), Memory = new CheckBox(), Notifications = new CheckBox(), Taskbar = new CheckBox();
    readonly Label title = TokcatUi.Label("任务总览", 20, TokcatUi.Text);
    readonly Label subtitle = TokcatUi.Label("TASKS  /  本地 Agent 的最近 7 天", 9, TokcatUi.Secondary);
    readonly Label selectionTitle = TokcatUi.Label("选择任务，查看详情", 12, TokcatUi.Text);
    readonly Label selectionMeta = TokcatUi.Label("选中后可阅读对话、打开项目或标记已读。", 9, TokcatUi.Secondary);
    readonly Label empty = TokcatUi.Label("尚未发现任务\n照常使用 Agent，本地记录会自动出现在这里。", 11, TokcatUi.Secondary);
    readonly Label resultCount = TokcatUi.Label("等待本地记录", 9, TokcatUi.Secondary);
    readonly Label[] totals = new Label[4];
    readonly Panel tasks = new Panel(), settings = new Panel();
    readonly Button taskNav = TokcatUi.Button("任务总览", "tasks", true);
    readonly Button settingsNav = TokcatUi.Button("设置", "settings", false);
    public bool Updating;

    public TokcatMainWindow()
    {
        TokcatUi.StyleWindow(this); Text = "tokcat · Agent 监控";
        ClientSize = new Size(1180, 760); MinimumSize = new Size(900, 600);
        StartPosition = FormStartPosition.CenterScreen; KeyPreview = true;
        Panel rail = new Panel { Dock = DockStyle.Left, Width = 172, BackColor = TokcatUi.Surface, Padding = new Padding(14) };
        Label brand = TokcatUi.Label("tokcat", 18, TokcatUi.Text); brand.SetBounds(52, 22, 110, 34);
        PictureBox logo = new PictureBox { Image = TokcatUi.Icon("cat", TokcatUi.Accent, 30), Bounds = new Rectangle(16, 24, 30, 30) };
        logo.Disposed += delegate { logo.Image.Dispose(); };
        Label tagline = TokcatUi.Label("多 Agent 状态监控", 8, TokcatUi.Secondary); tagline.SetBounds(18, 64, 150, 24);
        taskNav.SetBounds(12, 110, 148, 40); UsageButton.SetBounds(12, 158, 148, 40);
        settingsNav.Dock = DockStyle.Bottom; settingsNav.Height = 40;
        QuitButton.Dock = DockStyle.Bottom; QuitButton.Height = 36;
        rail.Controls.AddRange(new Control[] { brand, logo, tagline, taskNav, UsageButton, settingsNav, QuitButton });

        Panel content = new Panel { Dock = DockStyle.Fill, Padding = new Padding(24, 18, 24, 12) };
        Panel header = new Panel { Dock = DockStyle.Top, Height = 72 };
        title.SetBounds(0, 0, 420, 36); subtitle.SetBounds(2, 44, 500, 24);
        RefreshButton.Anchor = AnchorStyles.Top | AnchorStyles.Right; RefreshButton.Location = new Point(674, 4);
        header.Controls.AddRange(new Control[] { title, subtitle, RefreshButton });
        header.Resize += delegate { RefreshButton.Left = header.ClientSize.Width - RefreshButton.Width; };
        Note.Dock = DockStyle.Bottom; Note.Height = 52; Note.Padding = new Padding(0, 8, 0, 0);
        tasks.Dock = DockStyle.Fill; settings.Dock = DockStyle.Fill; settings.Visible = false;
        content.Controls.Add(tasks); content.Controls.Add(settings); content.Controls.Add(Note); content.Controls.Add(header);
        Controls.Add(content); Controls.Add(rail);

        TableLayoutPanel cards = new TableLayoutPanel { Dock = DockStyle.Top, Height = 80, ColumnCount = 4, RowCount = 1 };
        string[] names = { "运行中", "需要你处理", "本轮结束", "失败 / 无活动" };
        string[] states = { "running", "waiting", "completed", "failed" };
        for (int i = 0; i < 4; i++)
        {
            cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            Panel card = new Panel { Dock = DockStyle.Fill, BackColor = TokcatUi.Surface, Margin = new Padding(0, 0, i == 3 ? 0 : 10, 12) };
            Label caption = TokcatUi.Label(names[i], 9, TokcatUi.Secondary); caption.SetBounds(14, 8, 140, 22); caption.AutoEllipsis = true;
            card.Resize += delegate { caption.Width = Math.Max(10, card.ClientSize.Width - 28); };
            totals[i] = TokcatUi.Label("—", 20, TokcatUi.StateColor(states[i])); totals[i].SetBounds(14, 29, 140, 34);
            card.Controls.Add(caption); card.Controls.Add(totals[i]); cards.Controls.Add(card, i, 0);
        }
        FlowLayoutPanel filters = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 44, WrapContents = false, Padding = new Padding(0, 6, 0, 0) };
        Label searchLabel = TokcatUi.Label("搜索", 9, TokcatUi.Secondary); searchLabel.Size = new Size(38, 28); searchLabel.TextAlign = ContentAlignment.MiddleLeft;
        Search.Width = 220; Search.BackColor = TokcatUi.Surface; Search.ForeColor = TokcatUi.Text; Search.AccessibleName = "搜索任务、项目或模型";
        Search.Margin = new Padding(0, 2, 12, 0);
        SourceFilter.DropDownStyle = ComboBoxStyle.DropDownList; SourceFilter.Width = 158; SourceFilter.AccessibleName = "按 Agent 筛选";
        SourceFilter.Items.AddRange(new object[] { "全部 Agent", "Codex", "Codex Work", "Claude Code", "WorkBuddy", "WorkBuddy AI", "DeepSeek Harness", "OpenClaw", "Kimi" }); SourceFilter.SelectedIndex = 0;
        StateFilter.DropDownStyle = ComboBoxStyle.DropDownList; StateFilter.Width = 138; StateFilter.AccessibleName = "按状态筛选";
        StateFilter.Items.AddRange(new object[] { "全部状态", "运行中", "需要你处理", "本轮结束", "失败 / 无活动", "未知 / 中断" }); StateFilter.SelectedIndex = 0;
        SourceFilter.BackColor = StateFilter.BackColor = TokcatUi.Surface; SourceFilter.ForeColor = StateFilter.ForeColor = TokcatUi.Text;
        filters.Controls.AddRange(new Control[] { searchLabel, Search, SourceFilter, StateFilter });
        resultCount.Dock = DockStyle.Top; resultCount.Height = 24;
        Panel table = new Panel { Dock = DockStyle.Fill, BackColor = TokcatUi.Surface, Padding = new Padding(1) };
        TokcatUi.StyleList(Sessions); Sessions.Dock = DockStyle.Fill; Sessions.AccessibleName = "最近七天的 Agent 任务";
        string[] columns = { "状态", "来源", "任务", "项目", "阶段", "模型", "输出 tokens", "输出 tok/s", "最后活动" };
        int[] widths = { 122, 130, 260, 210, 170, 125, 100, 95, 155 };
        for (int i = 0; i < columns.Length; i++) Sessions.Columns.Add(columns[i], widths[i]);
        empty.Dock = DockStyle.Fill; empty.TextAlign = ContentAlignment.MiddleCenter;
        table.Controls.Add(Sessions); table.Controls.Add(empty);
        Quota.Dock = DockStyle.Bottom; Quota.Height = 28; Quota.Padding = new Padding(0, 6, 0, 0); Quota.AutoEllipsis = true;
        Panel detail = new Panel { Dock = DockStyle.Bottom, Height = 126, Padding = new Padding(14, 12, 14, 8), BackColor = TokcatUi.Surface };
        selectionTitle.Dock = DockStyle.Top; selectionTitle.Height = 28; selectionTitle.AutoEllipsis = true;
        selectionMeta.Dock = DockStyle.Top; selectionMeta.Height = 40; selectionMeta.AutoEllipsis = true;
        FlowLayoutPanel actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 36, WrapContents = false };
        actions.Controls.AddRange(new Control[] { ConversationButton, ProjectButton, RecordButton, ReadButton });
        detail.Controls.Add(selectionMeta); detail.Controls.Add(selectionTitle); detail.Controls.Add(actions);
        tasks.Controls.Add(table); tasks.Controls.Add(Quota); tasks.Controls.Add(detail); tasks.Controls.Add(resultCount); tasks.Controls.Add(filters); tasks.Controls.Add(cards);
        BuildSettings(); SetSelection(null, null, null);
        taskNav.Click += delegate { ShowSettings(false); };
        settingsNav.Click += delegate { ShowSettings(true); };
        KeyDown += delegate(object sender, KeyEventArgs e) {
            if (e.Control && e.KeyCode == Keys.F) { ShowSettings(false); Search.Focus(); e.SuppressKeyPress = true; }
            if (e.KeyCode == Keys.F5) { RefreshButton.PerformClick(); e.SuppressKeyPress = true; }
            if (e.KeyCode == Keys.Escape && tasks.Visible) { Search.Clear(); SourceFilter.SelectedIndex = StateFilter.SelectedIndex = 0; e.SuppressKeyPress = true; }
        };
    }

    void BuildSettings()
    {
        settings.AutoScroll = true;
        FlowLayoutPanel stack = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(18), BackColor = TokcatUi.Surface };
        Label heading = TokcatUi.Label("任务栏与提醒", 14, TokcatUi.Text); heading.Size = new Size(600, 38); stack.Controls.Add(heading);
        CheckBox[] checks = { Taskbar, Cpu, Gpu, Memory, Notifications };
        string[] labels = { "显示任务栏监控", "任务栏显示 CPU", "任务栏显示 GPU", "任务栏显示内存", "启用任务状态通知" };
        for (int i = 0; i < checks.Length; i++)
        {
            checks[i].Text = labels[i]; checks[i].Size = new Size(600, 36); checks[i].ForeColor = TokcatUi.Text;
            checks[i].AccessibleName = labels[i]; stack.Controls.Add(checks[i]);
        }
        StripButton.Width = 160; stack.Controls.Add(StripButton);
        Label help = TokcatUi.Label("监控仅读取本地记录，无需 API 密钥。\n关闭主窗口后继续在任务栏运行；退出程序请使用左下角按钮。\n外观随启动时的 Windows 应用主题；GPU 仅在开启后采样。", 9, TokcatUi.Secondary);
        help.Size = new Size(600, 94); help.Margin = new Padding(0, 24, 0, 0); stack.Controls.Add(help);
        settings.Controls.Add(stack);
    }

    public void ShowSettings(bool visible)
    {
        tasks.Visible = !visible; settings.Visible = visible;
        title.Text = visible ? "设置" : "任务总览";
        subtitle.Text = visible ? "SETTINGS  /  任务栏、指标与通知" : "TASKS  /  本地 Agent 的最近 7 天";
        taskNav.BackColor = visible ? TokcatUi.Surface : TokcatUi.Selection;
        settingsNav.BackColor = visible ? TokcatUi.Selection : TokcatUi.Surface;
        taskNav.ForeColor = visible ? TokcatUi.Text : TokcatUi.Accent;
        settingsNav.ForeColor = visible ? TokcatUi.Accent : TokcatUi.Text;
    }

    public void SetTotals(int running, int waiting, int completed, int problems)
    {
        int[] values = { running, waiting, completed, problems };
        for (int i = 0; i < values.Length; i++) totals[i].Text = values[i].ToString();
    }

    public void SetResults(int visible, int total)
    {
        resultCount.Text = "显示 " + visible + " / " + total + " 项任务 · 双击或按 Enter 阅读对话";
        empty.Text = total == 0 ? "尚未发现任务\n照常使用 Agent，本地记录会自动出现在这里。" : "没有匹配的任务\n调整搜索条件，或按 Esc 清除筛选。";
        empty.Visible = visible == 0; if (empty.Visible) empty.BringToFront();
    }

    public void SetSelection(string name, string metadata, string state)
    {
        bool selected = !String.IsNullOrWhiteSpace(name);
        selectionTitle.Text = selected ? name : "选择任务，查看详情";
        selectionMeta.Text = selected ? metadata : "选中后可阅读对话、打开项目或标记已读。";
        selectionTitle.ForeColor = TokcatUi.Text;
        ConversationButton.Enabled = ProjectButton.Enabled = RecordButton.Enabled = ReadButton.Enabled = selected;
    }
}
