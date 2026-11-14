using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Windows.Forms;

public sealed class TokcatLauncherSettingsPage : UserControl
{
    readonly Color[] palette;
    readonly Func<TokcatLauncherSettings> readSettings;
    readonly Panel editorHost = new Panel { Dock = DockStyle.Fill };
    readonly Label status = new Label { Dock = DockStyle.Bottom, Height = 24, AutoEllipsis = true };
    public readonly ComboBox Sample = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 116 };
    public readonly ComboBox PreviewBackground = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 116 };
    public readonly Button OpenLauncher = new Button { Text = "打开启动框", Width = 124, Height = 28 };
    public readonly TokcatLauncherPreviewScene Preview;
    public TokcatLauncherSettingsWindow Editor { get; private set; }
    public event EventHandler SaveRequested;
    public event EventHandler OpenLauncherRequested;

    public TokcatLauncherSettingsPage(Color[] palette, Func<TokcatLauncherSettings> readSettings)
    {
        this.palette = palette; this.readSettings = readSettings;
        Dock = DockStyle.Fill; BackColor = palette[0]; ForeColor = palette[2];
        Font = new Font("Microsoft YaHei UI", 9);
        var previewArea = new Panel { Dock = DockStyle.Top, Height = 272, Padding = new Padding(0, 0, 0, 12) };
        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 40, WrapContents = false };
        toolbar.Controls.Add(new Label { Text = "实时预览", AutoSize = true, Padding = new Padding(0, 6, 10, 0) });
        Sample.Items.AddRange(new object[] { "空白输入", "应用搜索", "网页翻译", "计算结果" }); Sample.SelectedIndex = 1;
        Sample.AccessibleName = "预览内容";
        PreviewBackground.Items.AddRange(new object[] { "浅色背景", "深色背景" }); PreviewBackground.SelectedIndex = palette[1].GetBrightness() > 0.5f ? 0 : 1;
        PreviewBackground.AccessibleName = "预览背景";
        toolbar.Controls.AddRange(new Control[] { Sample, PreviewBackground, OpenLauncher });
        Preview = new TokcatLauncherPreviewScene(palette) { Dock = DockStyle.Fill };
        previewArea.Controls.Add(Preview); previewArea.Controls.Add(toolbar);
        status.Text = "更改选项即可查看预览，点击保存后应用。"; status.ForeColor = palette[3];
        Controls.Add(editorHost); Controls.Add(status); Controls.Add(previewArea);
        foreach (Control control in toolbar.Controls)
        {
            control.BackColor = palette[1]; control.ForeColor = palette[2];
            var button = control as Button;
            if (button != null) { button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderColor = palette[3]; }
        }
        Sample.SelectedIndexChanged += delegate { UpdatePreview(); };
        PreviewBackground.SelectedIndexChanged += delegate { UpdatePreview(); };
        OpenLauncher.Click += delegate { if (OpenLauncherRequested != null) OpenLauncherRequested(this, EventArgs.Empty); };
        ResetEditor(0);
    }

    void ResetEditor(int selectedTab)
    {
        if (Editor != null) { editorHost.Controls.Remove(Editor); Editor.Dispose(); }
        Editor = new TokcatLauncherSettingsWindow(readSettings(), palette);
        Editor.AppearanceChanged += delegate { status.Text = "预览已更新，点击保存后应用。"; UpdatePreview(); };
        Editor.SaveRequested += delegate { if (SaveRequested != null) SaveRequested(this, EventArgs.Empty); };
        Editor.DiscardRequested += delegate { ResetEditor(Editor.Tabs.SelectedIndex); status.Text = "已恢复已保存的设置。"; };
        Editor.EmbedIn(editorHost);
        Editor.Tabs.SelectedIndex = Math.Max(0, Math.Min(selectedTab, Editor.Tabs.TabCount - 1));
        UpdatePreview();
    }

    void UpdatePreview()
    {
        if (Editor == null) return;
        var draft = Editor.Settings.Copy(); draft.Skin = Editor.PreviewSkin; draft.AutoTextColor = Editor.PreviewAutomaticText;
        Preview.Configure(draft, Sample.SelectedIndex, PreviewBackground.SelectedIndex == 0);
    }

    public void AcceptSaved()
    {
        ResetEditor(Editor.Tabs.SelectedIndex);
        status.Text = "已保存。可点击「打开启动框」试用，或按快捷键唤出。";
    }
}

// A native child launcher renders the same input, result rows, colors and blur as
// the real popup. A generated wallpaper keeps preview independent of screen capture.
public sealed class TokcatLauncherPreviewScene : Panel
{
    public readonly TokcatLauncherWindow Launcher;
    Bitmap wallpaper, margins;
    bool light, updating;

    public TokcatLauncherPreviewScene(Color[] palette)
    {
        DoubleBuffered = true;
        Launcher = new TokcatLauncherWindow(palette) { IsPreview = true, TopLevel = false, TopMost = false, ShowInTaskbar = false };
        Launcher.Query.ReadOnly = true; Launcher.Query.TabStop = false; Launcher.Results.TabStop = false;
        Launcher.Radial.FrameChanged += delegate { RebuildBackground(); };
        Controls.Add(Launcher); Launcher.Show();
        Layout += delegate { RebuildBackground(); };
    }

    public void Configure(TokcatLauncherSettings draft, int sample, bool lightBackground)
    {
        light = lightBackground;
        Launcher.Appearance.Configure(draft.Skin, draft.AutoTextColor);
        switch (sample)
        {
            case 0: Launcher.Query.Text = ""; Launcher.SetResults(new TokcatLauncherResult[0], ""); break;
            case 2:
                Launcher.Query.Text = "tran+hello world";
                Launcher.SetResults(draft.RankedTranslations().Select(p => p.Request("hello world")).Where(r => r != null).Take(2), "翻译 · ↑↓ 选择 · Enter 打开网页");
                break;
            case 3:
                Launcher.Query.Text = "sqrt(9)+2^3";
                Launcher.SetResults(new[] { new TokcatLauncherResult { Title = "11", Detail = "计算 · 回车复制结果", Kind = "calculation", Value = "11", Key = "preview:calculator" } }, "Enter 复制结果 · Esc 关闭");
                break;
            default:
                Launcher.Query.Text = "应用";
                Launcher.SetResults(new[] {
                    new TokcatLauncherResult { Title = "记事本", Detail = "应用 · 预览", Kind = "application", Key = "preview:notepad", App = new TokcatLauncherApp { Name = "记事本", Target = Path.Combine(Environment.SystemDirectory, "notepad.exe") } },
                    new TokcatLauncherResult { Title = "计算器", Detail = "应用 · 预览", Kind = "application", Key = "preview:calculator", App = new TokcatLauncherApp { Name = "计算器", Target = Path.Combine(Environment.SystemDirectory, "calc.exe") } }
                }, "↑↓ 选择 · Enter 打开 · Esc 关闭");
                break;
        }
        RebuildBackground();
    }

    void RebuildBackground()
    {
        if (updating || ClientSize.Width < 1 || ClientSize.Height < 1) return;
        updating = true;
        try
        {
            if (wallpaper != null) wallpaper.Dispose();
            wallpaper = new Bitmap(ClientSize.Width, ClientSize.Height);
            using (var graphics = Graphics.FromImage(wallpaper))
            using (var gradient = new LinearGradientBrush(ClientRectangle,
                light ? Color.FromArgb(246, 244, 238) : Color.FromArgb(20, 25, 40),
                light ? Color.FromArgb(160, 200, 198) : Color.FromArgb(36, 67, 74), 25f))
            {
                graphics.FillRectangle(gradient, ClientRectangle);
                using (var accent = new SolidBrush(Color.FromArgb(45, light ? Color.White : Color.FromArgb(88, 140, 164))))
                    graphics.FillEllipse(accent, ClientSize.Width / 2, -100, 600, 500);
            }
            Launcher.Visible = !Launcher.Appearance.IsRadial;
            if (Launcher.Appearance.IsRadial) Launcher.Radial.Motion.Finish();
            Launcher.Location = new Point((ClientSize.Width - Launcher.Width) / 2, (ClientSize.Height - Launcher.Height) / 2);
            int x = Launcher.Appearance.MarginX, y = Launcher.Appearance.MarginY;
            using (var source = new Bitmap(Launcher.Width + 2 * x, Launcher.Height + 2 * y))
            using (var graphics = Graphics.FromImage(source))
            {
                graphics.Clear(light ? Color.WhiteSmoke : Color.FromArgb(20, 25, 40));
                graphics.DrawImage(wallpaper, new Rectangle(Point.Empty, source.Size), new Rectangle(Launcher.Left - x, Launcher.Top - y, source.Width, source.Height), GraphicsUnit.Pixel);
                Launcher.Appearance.UsePreviewBackground(source);
            }
            if (margins != null) margins.Dispose(); margins = Launcher.Appearance.CreateFeatheredMargins();
            Invalidate(true);
        }
        finally { updating = false; }
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        if (wallpaper != null) e.Graphics.DrawImageUnscaled(wallpaper, 0, 0);
        else base.OnPaintBackground(e);
        if (margins != null) e.Graphics.DrawImageUnscaled(margins, Launcher.Left - Launcher.Appearance.MarginX, Launcher.Top - Launcher.Appearance.MarginY);
        if (Launcher.Appearance.IsRadial)
        {
            using (var frame = Launcher.Radial.Render())
            {
                float scale = Math.Min(1f, Math.Min((ClientSize.Width - 16f) / frame.Width, (ClientSize.Height - 16f) / frame.Height));
                int width = (int)(frame.Width * scale), height = (int)(frame.Height * scale);
                e.Graphics.DrawImage(frame, new Rectangle((ClientSize.Width - width) / 2, (ClientSize.Height - height) / 2, width, height));
            }
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { if (wallpaper != null) wallpaper.Dispose(); if (margins != null) margins.Dispose(); }
        base.Dispose(disposing);
    }
}
