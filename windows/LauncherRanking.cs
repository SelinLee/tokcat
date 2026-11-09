using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

public static class TokcatLauncherRanking
{
    public static TokcatLauncherResult[] Build(string input, TokcatLauncherSettings settings,
        IEnumerable<TokcatLauncherMatch> applications, IEnumerable<TokcatEverythingFile> files,
        bool sourcesSettled, TokcatLauncherHistory recalled)
    {
        string text = (input ?? "").Trim();
        if (text.Length == 0) return History(settings);
        var results = new List<TokcatLauncherResult>();
        var appTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var match in applications)
        {
            appTargets.Add(match.Application.Target);
            results.Add(new TokcatLauncherResult
            {
                Title = match.Application.Name, Detail = "应用", Kind = "application", App = match.Application,
                Value = match.Application.Target, Key = "application:" + match.Application.Target, Score = 1200 - match.Score * 3
            });
        }
        foreach (var file in files)
        {
            if (appTargets.Contains(file.FullPath)) continue;
            results.Add(new TokcatLauncherResult
            {
                Title = file.Name, Detail = (file.IsFolder ? "文件夹 · " : "文件 · ") + file.FullPath,
                Kind = "file", Value = file.FullPath, Key = "file:" + file.FullPath, Score = FileScore(text, file.Name)
            });
        }
        if (text.Equals("setup", StringComparison.OrdinalIgnoreCase))
            results.Add(new TokcatLauncherResult { Title = "打开 tokcat 设置", Detail = "设置", Kind = "settings", Key = "settings", Score = 1500 });
        if (text.StartsWith(">") && text.Substring(1).Trim().Length > 0)
            results.Add(new TokcatLauncherResult { Title = "在 PowerShell 中执行", Detail = text.Substring(1).Trim(), Kind = "terminal", Value = text.Substring(1).Trim(), Key = "terminal:" + text.Substring(1).Trim(), Score = 1500 });

        var calculation = TokcatLauncherCalculator.Evaluate(text);
        if (calculation != null && calculation.Result != null)
            results.Add(new TokcatLauncherResult
            {
                Title = calculation.Result, Detail = "计算 · 回车复制结果", Kind = "calculation", Value = calculation.Result,
                Key = "calculator:" + text, Score = Regex.IsMatch(text, @"^\s*[+\-]?\d+(?:\.\d+)?\s*$") ? 700 : 1300
            });
        foreach (var command in settings.Commands.Where(c => c.Enabled))
        {
            int score = KeywordScore(text, command);
            if (score == 0) continue;
            results.Add(new TokcatLauncherResult
            {
                Title = string.IsNullOrWhiteSpace(command.Name) ? command.Keyword : command.Name,
                Detail = "命令 · " + command.Value, Kind = "terminal", Value = command.Value,
                Key = "command:" + command.Keyword, Score = score
            });
        }
        foreach (var website in settings.Websites.Where(w => w.Enabled))
        {
            string prefix = website.Keyword + " ";
            bool withQuery = text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
            string query = withQuery ? text.Substring(prefix.Length).Trim() : "";
            int score = withQuery ? 1400 : KeywordScore(text, website);
            if (score == 0) continue;
            bool search = website.Value.Contains("{query}");
            if (withQuery && (!search || query.Length == 0)) continue;
            bool needsQuery = search && query.Length == 0;
            results.Add(new TokcatLauncherResult
            {
                Title = string.IsNullOrWhiteSpace(website.Name) ? website.Keyword : website.Name,
                Detail = needsQuery ? "输入搜索内容" : "网站 · " + (search ? query : website.Value),
                Kind = needsQuery ? "fill" : "website",
                Value = needsQuery ? prefix : website.Value.Replace("{query}", Uri.EscapeDataString(query)),
                Key = "website:" + website.Keyword, Score = score
            });
        }
        Uri direct = TokcatLauncherResolver.HttpUrl(text, true);
        if (direct != null)
            results.Add(new TokcatLauncherResult
            {
                Title = "打开网站", Detail = direct.AbsoluteUri, Kind = "website", Value = direct.AbsoluteUri,
                Key = "url:" + direct.AbsoluteUri, Score = text.Contains("://") ? 1450 : 650
            });
        if (recalled != null && !results.Any(r => string.Equals(r.Key, recalled.ActionKey, StringComparison.OrdinalIgnoreCase)))
        {
            var historyResult = FromHistory(recalled);
            historyResult.Score = 900;
            results.Add(historyResult);
        }
        if (results.Count == 0 && sourcesSettled && calculation == null && !text.StartsWith(">") && !text.StartsWith("="))
        {
            var engine = settings.Websites.FirstOrDefault(w => w.Enabled && w.Value.Contains("{query}"));
            string template = engine == null ? "https://www.bing.com/search?q={query}" : engine.Value;
            results.Add(new TokcatLauncherResult
            {
                Title = "搜索网页 · " + text,
                Detail = (engine == null ? "Bing" : engine.Name) + " · 回车在浏览器搜索",
                Kind = "website", Value = template.Replace("{query}", Uri.EscapeDataString(text)),
                Key = "search:" + template.Replace("{query}", Uri.EscapeDataString(text)), Score = 100
            });
        }
        foreach (var result in results)
        {
            result.Score += settings.UsageBoost(result.Key);
            if (recalled != null && string.Equals(result.Key, recalled.ActionKey, StringComparison.OrdinalIgnoreCase)) result.Score += 300;
        }
        return results.GroupBy(r => r.Key, StringComparer.OrdinalIgnoreCase).Select(g => g.OrderByDescending(r => r.Score).First())
            .OrderByDescending(r => r.Score).ThenBy(r => r.Title, StringComparer.CurrentCultureIgnoreCase).Take(7).ToArray();
    }

    static int KeywordScore(string text, TokcatLauncherShortcut entry)
    {
        if (text.Equals(entry.Keyword, StringComparison.OrdinalIgnoreCase)) return 1400;
        if (entry.Keyword.StartsWith(text, StringComparison.OrdinalIgnoreCase)) return 850;
        if (!string.IsNullOrEmpty(entry.Name) && entry.Name.IndexOf(text, StringComparison.OrdinalIgnoreCase) >= 0) return 750;
        return 0;
    }

    static int FileScore(string text, string name)
    {
        if (name.Equals(text, StringComparison.OrdinalIgnoreCase)) return 900;
        string stem;
        try { stem = Path.GetFileNameWithoutExtension(name); }
        catch (ArgumentException) { stem = name; }
        if (stem.Equals(text, StringComparison.OrdinalIgnoreCase)) return 880;
        if (name.StartsWith(text, StringComparison.OrdinalIgnoreCase)) return 820;
        return name.IndexOf(text, StringComparison.OrdinalIgnoreCase) >= 0 ? 780 : 650;
    }

    public static TokcatLauncherResult[] History(TokcatLauncherSettings settings)
    {
        return settings.History.Select((entry, index) =>
        {
            var result = FromHistory(entry);
            result.Score = 900 - index * 2 + settings.UsageBoost(result.Key);
            return result;
        }).GroupBy(r => r.Key, StringComparer.OrdinalIgnoreCase).Select(g => g.OrderByDescending(r => r.Score).First())
            .OrderByDescending(r => r.Score).Take(7).ToArray();
    }

    static TokcatLauncherResult FromHistory(TokcatLauncherHistory entry)
    {
        return new TokcatLauncherResult
        {
            Title = entry.Application == null ? entry.Text : entry.Application.Name,
            Detail = "历史记录 · " + entry.Text, App = entry.Application,
            Kind = entry.Kind ?? (entry.Application == null ? "fill" : "application"),
            Value = entry.Value ?? (entry.Application == null ? entry.Text : entry.Application.Target), Key = entry.ActionKey, Input = entry.Text
        };
    }
}
