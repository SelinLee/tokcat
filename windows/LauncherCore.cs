using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

public sealed class TokcatLauncherApp
{
    public string Name { get; set; }
    public string Target { get; set; }
    public bool Packaged { get; set; }
    public string Alias { get; set; }
}

public sealed class TokcatLauncherShortcut
{
    public string Keyword { get; set; }
    public string Name { get; set; }
    public string Value { get; set; }
    public bool Enabled { get; set; }
}

public sealed class TokcatLauncherHistory
{
    public string Text { get; set; }
    public TokcatLauncherApp Application { get; set; }
}

public sealed class TokcatLauncherSettings
{
    public int Version { get; set; }
    public bool Enabled { get; set; }
    public int Modifiers { get; set; }
    public int Key { get; set; }
    public int? X { get; set; }
    public int? Y { get; set; }
    public List<TokcatLauncherShortcut> Commands { get; set; }
    public List<TokcatLauncherShortcut> Websites { get; set; }
    public List<TokcatLauncherHistory> History { get; set; }

    public TokcatLauncherSettings()
    {
        Version = 1;
        Enabled = true;
        Modifiers = 1;
        Key = 32;
        Commands = new List<TokcatLauncherShortcut>();
        Websites = new List<TokcatLauncherShortcut>
        {
            Website("baidu", "百度搜索", "https://www.baidu.com/s?wd={query}"),
            Website("google", "Google 搜索", "https://www.google.com/search?q={query}"),
            Website("bing", "Bing 搜索", "https://www.bing.com/search?q={query}"),
            Website("github", "GitHub", "https://github.com")
        };
        History = new List<TokcatLauncherHistory>();
    }

    static TokcatLauncherShortcut Website(string keyword, string name, string value)
    {
        return new TokcatLauncherShortcut { Keyword = keyword, Name = name, Value = value, Enabled = true };
    }

    public void Validate()
    {
        if (Version != 1) throw new InvalidDataException("启动器设置版本不受支持。");
        if ((Modifiers & ~7) != 0 || (Modifiers & 3) == 0 || Key < 8 || Key > 254)
            throw new InvalidDataException("快捷键需要包含 Ctrl 或 Alt，以及一个普通按键。");
        if (Commands == null || Websites == null || History == null || Commands.Count + Websites.Count > 200)
            throw new InvalidDataException("启动器设置内容无效。");
        var keywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "setup" };
        foreach (var entry in Commands.Concat(Websites))
        {
            if (entry == null || !Regex.IsMatch(entry.Keyword ?? "", @"^[\p{L}\p{N}_-]{1,40}$") ||
                !keywords.Add(entry.Keyword) || TokcatLauncherCalculator.Evaluate(entry.Keyword) != null)
                throw new InvalidDataException("关键词需唯一，由 1–40 个字母、数字、中文、下划线或短横线组成。");
            if (string.IsNullOrWhiteSpace(entry.Value) || entry.Value.Length > 8192)
                throw new InvalidDataException("请填写有效的命令或网址。");
        }
        foreach (var website in Websites)
            if (TokcatLauncherResolver.HttpUrl(website.Value.Replace("{query}", "test"), false) == null)
                throw new InvalidDataException("网站地址需要以 http:// 或 https:// 开头。");
        History = History.Where(h => h != null && !string.IsNullOrWhiteSpace(h.Text) && h.Text.Length <= 8192).Take(50).ToList();
    }

    static JavaScriptSerializer Serializer()
    {
        return new JavaScriptSerializer { MaxJsonLength = 1048576, RecursionLimit = 32 };
    }

    public static TokcatLauncherSettings Load(string path)
    {
        if (!File.Exists(path)) return new TokcatLauncherSettings();
        if (new FileInfo(path).Length > 1048576) throw new InvalidDataException("启动器设置文件过大。");
        string text = File.ReadAllText(path, Encoding.UTF8);
        var raw = Serializer().DeserializeObject(text) as Dictionary<string, object>;
        if (raw == null || !raw.ContainsKey("Version")) throw new InvalidDataException("启动器设置格式无效。");
        var settings = Serializer().Deserialize<TokcatLauncherSettings>(text);
        settings.Validate();
        return settings;
    }

    public TokcatLauncherSettings Copy()
    {
        return Serializer().Deserialize<TokcatLauncherSettings>(Serializer().Serialize(this));
    }

    public void Save(string path)
    {
        Validate();
        if (File.Exists(path)) Load(path);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
        string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temp, Serializer().Serialize(this), new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(temp, path, null);
            else File.Move(temp, path);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    public void Remember(string text, TokcatLauncherApp app)
    {
        History.RemoveAll(h => string.Equals(h.Text, text, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(h.Application == null ? null : h.Application.Target, app == null ? null : app.Target, StringComparison.OrdinalIgnoreCase));
        History.Insert(0, new TokcatLauncherHistory { Text = text, Application = app });
        if (History.Count > 50) History.RemoveRange(50, History.Count - 50);
    }
}

public sealed class TokcatLauncherCalculation
{
    public string Result { get; set; }
    public string Error { get; set; }
}

// Bounded recursive descent follows the same precedence as LauncherCalculator.swift.
public static class TokcatLauncherCalculator
{
    static readonly HashSet<string> Functions = new HashSet<string>
    {
        "sqrt", "abs", "round", "floor", "ceil", "sin", "cos", "tan", "log", "log10", "log2", "ln", "exp", "pow", "min", "max"
    };

    public static TokcatLauncherCalculation Evaluate(string input)
    {
        string text = (input ?? "").Trim();
        if (text.Length == 0 || text.StartsWith(">")) return null;
        bool explicitMode = text.StartsWith("=");
        if (explicitMode) text = text.Substring(1);
        text = text.Normalize(NormalizationForm.FormKC).ToLowerInvariant().Replace("×", "*").Replace("÷", "/").Replace("−", "-").Replace("π", "pi");
        if (!explicitMode && !Regex.IsMatch(text, @"^(?:[\d.(+\-]|pi\b|e(?=\s*[+\-*/^%])|(?:sqrt|abs|round|floor|ceil|sin|cos|tan|log\d*|ln|exp|pow|min|max)\s*\()")) return null;
        if (text.Length > 1024) return new TokcatLauncherCalculation { Error = "算式过长，请缩短后再试。" };
        if (!explicitMode && Regex.Matches(text, @"(?<![\d.])[a-z]+\d*").Cast<Match>().Any(m => m.Value != "pi" && m.Value != "e" && !Functions.Contains(m.Value))) return null;
        try
        {
            double value = new Parser(text).Parse();
            return new TokcatLauncherCalculation { Result = (value == 0 ? 0 : value).ToString("G15", CultureInfo.InvariantCulture).ToLowerInvariant() };
        }
        catch (FormatException error) { return new TokcatLauncherCalculation { Error = error.Message }; }
    }

    sealed class Parser
    {
        readonly string text;
        int position, depth;
        public Parser(string text) { this.text = text; }
        char Next { get { SkipSpace(); return position < text.Length ? text[position] : '\0'; } }
        void SkipSpace() { while (position < text.Length && char.IsWhiteSpace(text[position])) position++; }
        bool Take(char value) { if (Next != value) return false; position++; return true; }
        static double Checked(double value)
        {
            if (double.IsNaN(value) || double.IsInfinity(value)) throw new FormatException("结果超出可计算范围。");
            return value;
        }
        public double Parse()
        {
            double value = Sum();
            if (Next != '\0') throw new FormatException("请检查括号和运算符。");
            return Checked(value);
        }
        double Sum()
        {
            double value = Product();
            while (Next == '+' || Next == '-')
            {
                char operation = Next; position++;
                double right = Product();
                value = Checked(operation == '+' ? value + right : value - right);
            }
            return value;
        }
        double Product()
        {
            double value = Unary();
            while (Next == '*' || Next == '/')
            {
                char operation = Next; position++;
                double right = Unary();
                if (operation == '/' && right == 0) throw new FormatException("不能除以 0。");
                value = Checked(operation == '*' ? value * right : value / right);
            }
            return value;
        }
        double Unary()
        {
            if (++depth > 64) throw new FormatException("算式嵌套过深。");
            try
            {
                if (Take('+')) return Unary();
                if (Take('-')) return -Unary();
                return Power();
            }
            finally { depth--; }
        }
        double Power()
        {
            double value = Primary();
            while (Take('%')) value /= 100;
            if (Take('^')) value = Checked(Math.Pow(value, Unary()));
            else if (Next == '*' && position + 1 < text.Length && text[position + 1] == '*')
            {
                position += 2;
                value = Checked(Math.Pow(value, Unary()));
            }
            return value;
        }
        double Primary()
        {
            if (Take('('))
            {
                double value = Sum();
                if (!Take(')')) throw new FormatException("请补全右括号。");
                return value;
            }
            if (char.IsLetter(Next))
            {
                int start = position++;
                while (position < text.Length && char.IsLetterOrDigit(text[position])) position++;
                string name = text.Substring(start, position - start);
                if (name == "pi") return Math.PI;
                if (name == "e") return Math.E;
                if (!Functions.Contains(name)) throw new FormatException("不支持的函数。");
                if (!Take('(')) throw new FormatException("函数后需要括号。");
                var arguments = new List<double>();
                if (Next != ')')
                {
                    arguments.Add(Sum());
                    while (Take(',')) arguments.Add(Sum());
                }
                if (!Take(')')) throw new FormatException("请补全右括号。");
                return Function(name, arguments);
            }
            var match = Regex.Match(text.Substring(position), @"^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+\-]?\d+)?");
            double number;
            if (!match.Success || !double.TryParse(match.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
                throw new FormatException("请继续输入算式。");
            position += match.Length;
            return Checked(number);
        }
        static double Function(string name, List<double> values)
        {
            if (name == "min" || name == "max")
            {
                if (values.Count == 0) throw new FormatException("请至少输入一个参数。");
                return name == "min" ? values.Min() : values.Max();
            }
            if (name == "pow")
            {
                if (values.Count != 2) throw new FormatException("pow() 需要两个参数。");
                return Checked(Math.Pow(values[0], values[1]));
            }
            if (values.Count != 1) throw new FormatException("函数需要一个参数。");
            double x = values[0];
            switch (name)
            {
                case "sqrt": return Checked(Math.Sqrt(x));
                case "abs": return Math.Abs(x);
                case "round": return Math.Round(x, MidpointRounding.AwayFromZero);
                case "floor": return Math.Floor(x);
                case "ceil": return Math.Ceiling(x);
                case "sin": return Checked(Math.Sin(x));
                case "cos": return Checked(Math.Cos(x));
                case "tan": return Checked(Math.Tan(x));
                case "exp": return Checked(Math.Exp(x));
                default:
                    if (x <= 0) throw new FormatException("对数参数必须大于 0。");
                    return name == "ln" ? Math.Log(x) : name == "log2" ? Math.Log(x, 2) : Math.Log10(x);
            }
        }
    }
}

public static class TokcatLauncherResolver
{
    public static Uri HttpUrl(string input, bool allowBareDomain)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Any(char.IsWhiteSpace)) return null;
        bool explicitScheme = input.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || input.StartsWith("http://", StringComparison.OrdinalIgnoreCase);
        if (!explicitScheme && (!allowBareDomain || input.Contains("://"))) return null;
        Uri url;
        if (!Uri.TryCreate(explicitScheme ? input : "https://" + input, UriKind.Absolute, out url) ||
            (url.Scheme != "https" && url.Scheme != "http") || string.IsNullOrEmpty(url.Host) || !string.IsNullOrEmpty(url.UserInfo)) return null;
        string originalHost = input.Split('/', '?', '#')[0].Split(':')[0];
        bool ipv4 = Regex.IsMatch(originalHost, @"^\d{1,3}(?:\.\d{1,3}){3}$") && originalHost.Split('.').All(p => int.Parse(p) <= 255);
        if (!explicitScheme && url.Host != "localhost" && !ipv4 &&
            !Regex.IsMatch(url.IdnHost, @"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,}|xn--[a-z0-9-]+)$", RegexOptions.IgnoreCase)) return null;
        return url;
    }

    public static Uri Website(string input, IEnumerable<TokcatLauncherShortcut> shortcuts)
    {
        string text = input.Trim();
        if (text.StartsWith(">")) return null;
        string[] parts = new Regex(@"\s+").Split(text, 2);
        var shortcut = shortcuts.FirstOrDefault(s => s.Enabled && string.Equals(s.Keyword, parts[0], StringComparison.OrdinalIgnoreCase));
        if (shortcut == null) return HttpUrl(text, true);
        string query = parts.Length > 1 ? parts[1].Trim() : "";
        bool search = shortcut.Value.Contains("{query}");
        if (search == (query.Length == 0)) return null;
        return HttpUrl(shortcut.Value.Replace("{query}", Uri.EscapeDataString(query)), false);
    }
}

public sealed class TokcatLauncherIndex
{
    sealed class Entry
    {
        public TokcatLauncherApp App;
        public string[] Terms;
    }
    readonly Entry[] entries;
    public TokcatLauncherIndex(IEnumerable<TokcatLauncherApp> apps)
    {
        entries = apps.Select(app => new Entry
        {
            App = app,
            Terms = new[] { Normalize(app.Name), Normalize(Latin(app.Name)), Normalize(app.Alias),
                Normalize(app.Packaged ? app.Target : Path.GetFileNameWithoutExtension(app.Target)) }.Distinct().ToArray()
        }).ToArray();
    }
    public TokcatLauncherApp[] Search(string text)
    {
        string query = Normalize(text).Replace(" ", "");
        if (query.Length == 0) return new TokcatLauncherApp[0];
        return entries.Select(e => new { Entry = e, Score = e.Terms.Min(t => Score(t, query)) })
            .Where(e => e.Score < 100).OrderBy(e => e.Score).ThenBy(e => e.Entry.App.Name, StringComparer.CurrentCultureIgnoreCase)
            .Take(7).Select(e => e.Entry.App).ToArray();
    }
    static string Normalize(string text)
    {
        return Regex.Replace((text ?? "").Normalize(NormalizationForm.FormKD).ToLowerInvariant(), @"[^\p{L}\p{N}]+", " ").Trim();
    }
    static int Score(string term, string query)
    {
        string compact = term.Replace(" ", "");
        if (compact == query) return 0;
        if (compact.StartsWith(query, StringComparison.Ordinal)) return 10;
        if (compact.Contains(query)) return 30;
        if (query.Length >= 2 && string.Concat(term.Split(' ').Where(p => p.Length > 0).Select(p => p[0])) == query) return 40;
        if (query.Length >= 2)
        {
            int cursor = 0;
            foreach (char c in compact) if (cursor < query.Length && c == query[cursor]) cursor++;
            if (cursor == query.Length) return 50;
        }
        return 100;
    }

    [DllImport("icu.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern IntPtr utrans_openU(string id, int length, int direction, IntPtr rules, int rulesLength, IntPtr parseError, ref int status);
    [DllImport("icu.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern void utrans_transUChars(IntPtr transform, StringBuilder text, ref int length, int capacity, int start, ref int limit, ref int status);
    [DllImport("icu.dll", CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
    static extern void utrans_close(IntPtr transform);
    static string Latin(string text)
    {
        if (!text.Any(c => c > 127)) return text;
        IntPtr transform = IntPtr.Zero;
        try
        {
            int status = 0;
            const string identifier = "Any-Latin; Latin-ASCII";
            transform = utrans_openU(identifier, identifier.Length, 0, IntPtr.Zero, 0, IntPtr.Zero, ref status);
            if (transform == IntPtr.Zero || status > 0) return text;
            var buffer = new StringBuilder(text, Math.Max(1024, text.Length * 20));
            int length = text.Length, limit = length;
            status = 0;
            utrans_transUChars(transform, buffer, ref length, buffer.Capacity, 0, ref limit, ref status);
            return status > 0 ? text : buffer.ToString();
        }
        catch (DllNotFoundException) { return text; }
        catch (EntryPointNotFoundException) { return text; }
        finally { if (transform != IntPtr.Zero) utrans_close(transform); }
    }
}

public static class TokcatLauncherCatalog
{
    public static TokcatLauncherApp[] Scan()
    {
        var apps = new Dictionary<string, TokcatLauncherApp>(StringComparer.OrdinalIgnoreCase);
        var roots = new[] { Environment.SpecialFolder.StartMenu, Environment.SpecialFolder.CommonStartMenu,
            Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.CommonDesktopDirectory };
        foreach (var root in roots) ScanDirectory(Environment.GetFolderPath(root), apps, 0);
        object shell = null, folder = null, items = null;
        try
        {
            shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application"));
            folder = shell.GetType().InvokeMember("NameSpace", System.Reflection.BindingFlags.InvokeMethod, null, shell, new object[] { "shell:AppsFolder" });
            if (folder != null)
            {
                items = folder.GetType().InvokeMember("Items", System.Reflection.BindingFlags.InvokeMethod, null, folder, null);
                int count = Convert.ToInt32(items.GetType().InvokeMember("Count", System.Reflection.BindingFlags.GetProperty, null, items, null));
                for (int i = 0; i < Math.Min(count, 3000); i++)
                {
                    object item = items.GetType().InvokeMember("Item", System.Reflection.BindingFlags.InvokeMethod, null, items, new object[] { i });
                    try
                    {
                        string name = (string)item.GetType().InvokeMember("Name", System.Reflection.BindingFlags.GetProperty, null, item, null);
                        string target = (string)item.GetType().InvokeMember("Path", System.Reflection.BindingFlags.GetProperty, null, item, null);
                        if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(target))
                        {
                            TokcatLauncherApp existing;
                            if (apps.TryGetValue(name, out existing)) existing.Alias = Path.IsPathRooted(target) ? Path.GetFileNameWithoutExtension(target) : target;
                            else apps[name] = new TokcatLauncherApp { Name = name, Target = target, Packaged = !Path.IsPathRooted(target) };
                        }
                    }
                    finally { if (item != null) Marshal.FinalReleaseComObject(item); }
                }
            }
        }
        catch (COMException) { }
        catch (System.Reflection.TargetInvocationException) { }
        finally
        {
            if (items != null) Marshal.FinalReleaseComObject(items);
            if (folder != null) Marshal.FinalReleaseComObject(folder);
            if (shell != null) Marshal.FinalReleaseComObject(shell);
        }
        return apps.Values.ToArray();
    }
    static void ScanDirectory(string directory, Dictionary<string, TokcatLauncherApp> apps, int depth)
    {
        if (depth > 8 || apps.Count >= 3000 || string.IsNullOrEmpty(directory) || !Directory.Exists(directory)) return;
        try
        {
            foreach (string file in Directory.GetFiles(directory))
            {
                string extension = Path.GetExtension(file).ToLowerInvariant();
                if (extension != ".lnk" && extension != ".exe" && extension != ".appref-ms") continue;
                string name = Path.GetFileNameWithoutExtension(file);
                if (!apps.ContainsKey(name)) apps[name] = new TokcatLauncherApp { Name = name, Target = file };
            }
            foreach (string child in Directory.GetDirectories(directory))
                if ((File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0) ScanDirectory(child, apps, depth + 1);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
