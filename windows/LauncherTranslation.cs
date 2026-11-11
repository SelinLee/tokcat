using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

public sealed class TokcatLauncherTranslationInput
{
    public string Text { get; private set; }
    public static TokcatLauncherTranslationInput Parse(string input)
    {
        string value = (input ?? "").Trim();
        if (!value.StartsWith("tran", StringComparison.OrdinalIgnoreCase) ||
            (value.Length > 4 && value[4] != '+' && !char.IsWhiteSpace(value[4]))) return null;
        value = value.Substring(4).Trim();
        if (value.StartsWith("+")) value = value.Substring(1);
        return new TokcatLauncherTranslationInput { Text = value.Trim() };
    }
    public bool IsDictionaryCandidate
    {
        get { return Text.Length > 0 && Text.Length <= 128 && Regex.IsMatch(Text, @"^\p{L}(?:[\p{L}\p{M}'’\-]*\p{L})?$"); }
    }
}

public sealed class TokcatLauncherTranslationProvider
{
    public string Id { get; set; }
    public string Name { get; set; }
    public string UrlTemplate { get; set; }
    public bool Enabled { get; set; }
    public TokcatLauncherTranslationProvider() { Id = Guid.NewGuid().ToString("D"); Enabled = true; }
    public static List<TokcatLauncherTranslationProvider> Defaults()
    {
        return new List<TokcatLauncherTranslationProvider>
        {
            new TokcatLauncherTranslationProvider { Id = "750f5809-c799-4e7f-b4c5-cf765d7b0001", Name = "Google 翻译", UrlTemplate = "https://translate.google.com/?sl=auto&tl=zh-CN&text={query}&op=translate" },
            new TokcatLauncherTranslationProvider { Id = "750f5809-c799-4e7f-b4c5-cf765d7b0002", Name = "Bing 翻译", UrlTemplate = "https://www.bing.com/translator?from=auto&to=zh-Hans&text={query}" }
        };
    }
    public void Validate()
    {
        Guid id;
        if (!Guid.TryParse(Id, out id) || string.IsNullOrWhiteSpace(Name) || Name.Length > 200)
            throw new InvalidDataException("请填写翻译方式名称。");
        if (string.IsNullOrEmpty(UrlTemplate) || UrlTemplate.Length > 8192 || !UrlTemplate.Contains("{query}"))
            throw new InvalidDataException("翻译地址需包含 {query}，用于填入待翻译内容。");
        var url = TokcatLauncherResolver.HttpUrl(UrlTemplate.Replace("{query}", "tokcat-query"), false);
        if (url == null || url.Host.IndexOf("tokcat-query", StringComparison.OrdinalIgnoreCase) >= 0)
            throw new InvalidDataException("翻译地址需为 HTTP(S)，将 {query} 放在路径或参数中。");
    }
    public TokcatLauncherResult Request(string text)
    {
        if (!Enabled || string.IsNullOrWhiteSpace(text)) return null;
        Validate();
        return new TokcatLauncherResult { Title = Name, Detail = text, Kind = "translation",
            Value = UrlTemplate.Replace("{query}", Uri.EscapeDataString(text)), Key = "translation:" + Id };
    }
}

// Windows has no Dictionary Services equivalent. An optional UTF-8 JSON dictionary
// keeps exact-word lookup local; an absent dictionary falls through to web providers.
public sealed class TokcatLauncherDictionary
{
    string cachedPath;
    long cachedLength, cachedWrite;
    Dictionary<string, string> entries;
    public string Lookup(string path, string text)
    {
        var input = TokcatLauncherTranslationInput.Parse("tran+" + text);
        if (!input.IsDictionaryCandidate || string.IsNullOrWhiteSpace(path)) return null;
        var info = new FileInfo(path);
        if (!info.Exists) return null;
        if (info.Length > 8 * 1024 * 1024) throw new InvalidDataException("本地词典不能超过 8 MiB。");
        long write = info.LastWriteTimeUtc.Ticks;
        if (entries == null || cachedPath != info.FullName || cachedWrite != write || cachedLength != info.Length)
        {
            string json;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (stream.Length > 8 * 1024 * 1024) throw new InvalidDataException("本地词典不能超过 8 MiB。");
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    var buffer = new char[8192]; var content = new StringBuilder(); int count;
                    while ((count = reader.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        if (content.Length + count > 8 * 1024 * 1024) throw new InvalidDataException("本地词典不能超过 8 MiB。");
                        content.Append(buffer, 0, count);
                    }
                    json = content.ToString();
                }
            }
            var raw = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024, RecursionLimit = 8 }.DeserializeObject(json) as Dictionary<string, object>;
            if (raw == null || raw.Any(p => !(p.Value is string))) throw new InvalidDataException("本地词典需为单词与释义组成的 JSON 对象。");
            var next = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var pair in raw) next[pair.Key.Normalize(NormalizationForm.FormC)] = ((string)pair.Value).Trim();
            entries = next; cachedPath = info.FullName; cachedWrite = write; cachedLength = info.Length;
        }
        string definition;
        return entries.TryGetValue(text.Normalize(NormalizationForm.FormC), out definition) && definition.Length > 0 ? definition : null;
    }
}
