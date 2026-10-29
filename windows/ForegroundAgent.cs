using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

// Identify only the foreground application's executable, never its title or contents.
public static class TokcatForegroundAgent {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint process);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref uint length);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint parameter, out bool value, uint flags);

    public static string SourceForExecutable(string path) {
        if (string.IsNullOrEmpty(path)) return null;
        string name=Path.GetFileName(path).ToLowerInvariant();
        switch(name) {
            case "codex.exe": return "Codex";
            // Current Store builds of Codex ship their GUI as ChatGPT.exe.
            case "chatgpt.exe": return path.IndexOf(@"\OpenAI.Codex_",StringComparison.OrdinalIgnoreCase)>=0 ? "Codex" : null;
            case "claude.exe": return "Claude Code";
            case "workbuddy.exe": return "WorkBuddy";
            case "workbuddyai.exe": case "workbuddy-ai.exe": case "workbuddy ai.exe": return "WorkBuddy AI";
            case "deepseek harness.exe": case "dsh desktop.exe": return "DeepSeek Harness";
            default: return null;
        }
    }
    public static string CurrentSource() {
        uint process; if(GetWindowThreadProcessId(GetForegroundWindow(),out process)==0) return null;
        IntPtr handle=OpenProcess(0x1000,false,process); if(handle==IntPtr.Zero) return null;
        try { uint length=32768; var path=new StringBuilder((int)length); return QueryFullProcessImageName(handle,0,path,ref length) ? SourceForExecutable(path.ToString()) : null; }
        finally { CloseHandle(handle); }
    }
    public static bool AnimationsEnabled { get { bool enabled; return !SystemParametersInfo(0x1042,0,out enabled,0) || enabled; } }
}
