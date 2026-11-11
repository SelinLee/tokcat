using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class TokcatEverythingFile
{
    public string Name { get; set; }
    public string FullPath { get; set; }
    public bool IsFolder { get; set; }
}

public sealed class TokcatEverythingReply : EventArgs
{
    public string Query { get; set; }
    public string Error { get; set; }
    public TokcatEverythingFile[] Files { get; set; }
}

// Unicode query IPC follows voidtools' documented EVERYTHING_IPC_QUERYW/LISTW.
// https://www.voidtools.com/support/everything/sdk/ipc/
public sealed class TokcatEverythingSearch : NativeWindow, IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct CopyData
    {
        public IntPtr Id;
        public int Length;
        public IntPtr Data;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SendMessageTimeout(IntPtr window, int message, IntPtr sender,
        ref CopyData data, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")]
    static extern bool ChangeWindowMessageFilterEx(IntPtr window, uint message, uint action, IntPtr changeInfo);

    const int CopyDataMessage = 0x004A;
    const int MaxResults = 128;
    const int MaxReplyBytes = 4 * 1024 * 1024;
    readonly Timer deadline = new Timer { Interval = 4000 };
    IntPtr server;
    int sequence, activeId;
    string activeQuery;
    bool disposed;
    public event EventHandler<TokcatEverythingReply> Completed;

    public TokcatEverythingSearch()
    {
        CreateHandle(new CreateParams { Caption = "tokcat Everything queries", Parent = new IntPtr(-3) });
        ChangeWindowMessageFilterEx(Handle, CopyDataMessage, 1, IntPtr.Zero);
        deadline.Tick += delegate { Finish(null, "Everything 查询超时，请稍后重试。"); };
    }

    public static bool IsRunning
    {
        get { return ServerWindow() != IntPtr.Zero; }
    }

    static IntPtr ServerWindow()
    {
        IntPtr window = FindWindow("EVERYTHING_TASKBAR_NOTIFICATION", null);
        if (window == IntPtr.Zero) window = FindWindow("EVERYTHING_TASKBAR_NOTIFICATION_(1.5a)", null);
        return window;
    }

    public void Query(string text)
    {
        if (disposed) throw new ObjectDisposedException("TokcatEverythingSearch");
        Cancel();
        activeId = sequence = sequence == int.MaxValue ? 1 : sequence + 1;
        activeQuery = text;
        if (string.IsNullOrWhiteSpace(text) || text.Length > 8192 || text.IndexOf('\0') >= 0)
        {
            Finish(null, "请输入有效的文件名称或 Everything 搜索条件。");
            return;
        }
        server = ServerWindow();
        if (server == IntPtr.Zero)
        {
            Finish(null, "请先运行 Everything，再搜索文件。");
            return;
        }
        byte[] query;
        using (var stream = new MemoryStream())
        using (var writer = new BinaryWriter(stream, Encoding.Unicode))
        {
            // The protocol stores HWND in a DWORD on both x86 and x64.
            writer.Write(unchecked((uint)Handle.ToInt64()));
            writer.Write((uint)activeId);
            writer.Write((uint)4); // Match paths as well as file names.
            writer.Write((uint)0);
            writer.Write((uint)MaxResults);
            writer.Write(Encoding.Unicode.GetBytes(text + "\0"));
            query = stream.ToArray();
        }
        IntPtr buffer = Marshal.AllocHGlobal(query.Length);
        try
        {
            Marshal.Copy(query, 0, buffer, query.Length);
            var data = new CopyData { Id = new IntPtr(2), Length = query.Length, Data = buffer };
            IntPtr accepted;
            deadline.Start();
            IntPtr sent = SendMessageTimeout(server, CopyDataMessage, Handle, ref data, 0x0002, 250, out accepted);
            if (activeId != 0 && (sent == IntPtr.Zero || accepted == IntPtr.Zero))
                Finish(null, "无法连接 Everything，请检查它的运行状态及 IPC 支持。");
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public void Cancel()
    {
        deadline.Stop();
        activeId = 0;
        activeQuery = null;
    }

    void Finish(TokcatEverythingFile[] files, string error)
    {
        if (activeId == 0) return;
        string query = activeQuery;
        Cancel();
        var completed = Completed;
        if (completed != null) completed(this, new TokcatEverythingReply
        {
            Query = query, Error = error, Files = files ?? new TokcatEverythingFile[0]
        });
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == CopyDataMessage && activeId != 0 && message.LParam != IntPtr.Zero)
        {
            var data = (CopyData)Marshal.PtrToStructure(message.LParam, typeof(CopyData));
            if (data.Id.ToInt64() == activeId && (message.WParam == server || message.WParam == IntPtr.Zero))
            {
                if (data.Length < 28 || data.Length > MaxReplyBytes || data.Data == IntPtr.Zero)
                    Finish(null, "Everything 返回的数据格式无效。");
                else
                {
                    var payload = new byte[data.Length];
                    Marshal.Copy(data.Data, payload, 0, payload.Length);
                    try { Finish(ParseReply(payload), null); }
                    catch (InvalidDataException) { Finish(null, "Everything 返回的数据格式无效。"); }
                }
                message.Result = new IntPtr(1);
                return;
            }
        }
        base.WndProc(ref message);
    }

    public static TokcatEverythingFile[] ParseReply(byte[] data)
    {
        if (data == null || data.Length < 28 || data.Length > MaxReplyBytes)
            throw new InvalidDataException("Invalid Everything reply length.");
        uint count = BitConverter.ToUInt32(data, 20);
        if (count > MaxResults || 28 + count * 12 > data.Length)
            throw new InvalidDataException("Invalid Everything result count.");
        int stringsStart = 28 + (int)count * 12;
        var files = new List<TokcatEverythingFile>();
        for (int i = 0; i < count; i++)
        {
            int item = 28 + i * 12;
            uint flags = BitConverter.ToUInt32(data, item);
            string name = ReadString(data, BitConverter.ToUInt32(data, item + 4), stringsStart);
            string path = ReadString(data, BitConverter.ToUInt32(data, item + 8), stringsStart);
            string fullPath = path.Length == 0 ? name : path.TrimEnd('\\') + "\\" + name;
            if ((flags & 2) != 0 && fullPath.Length == 2 && fullPath[1] == ':') fullPath += "\\";
            if (string.IsNullOrWhiteSpace(fullPath)) continue;
            files.Add(new TokcatEverythingFile { Name = name, FullPath = fullPath, IsFolder = (flags & 3) != 0 });
        }
        return files.ToArray();
    }

    static string ReadString(byte[] data, uint start, int minimum)
    {
        if (start < minimum || start >= data.Length || start % 2 != 0)
            throw new InvalidDataException("Invalid Everything string offset.");
        int offset = (int)start, end = offset;
        while (end + 1 < data.Length && (data[end] != 0 || data[end + 1] != 0)) end += 2;
        if (end + 1 >= data.Length || end - offset > 65534)
            throw new InvalidDataException("Unterminated Everything result string.");
        return Encoding.Unicode.GetString(data, offset, end - offset);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        Cancel(); deadline.Dispose(); DestroyHandle();
    }
}
