using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

// Windows 10/11 include winsqlite3. Open the client's database read-only.
public static class TokcatWorkCatalog {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int size, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_type(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern double sqlite3_column_double(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_int(IntPtr stmt, int column);
    static byte[] Utf8(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
    static string Text(IntPtr stmt, int column) {
        IntPtr p = sqlite3_column_text(stmt, column); if (p == IntPtr.Zero) return null;
        int n = sqlite3_column_bytes(stmt, column); byte[] bytes = new byte[n]; Marshal.Copy(p, bytes, 0, n); return Encoding.UTF8.GetString(bytes);
    }
    static IntPtr Prepare(IntPtr db, string sql) {
        IntPtr stmt; if (sqlite3_prepare_v2(db, Utf8(sql), -1, out stmt, IntPtr.Zero) != 0) throw new InvalidOperationException("Work catalog query failed"); return stmt;
    }
    public sealed class Row { public string Host, Id, Title; public double Updated; public int? Status; }
    public sealed class BuddyRow { public string Id, Project, Title, Status, Model; public double Updated; }
    public static BuddyRow[] ReadBuddy(string path, double since) {
        IntPtr db; int result = sqlite3_open_v2(Utf8(path), out db, 1 | 0x8000, IntPtr.Zero);
        if (result != 0) { if (db != IntPtr.Zero) sqlite3_close(db); throw new InvalidOperationException("WorkBuddy database unavailable"); }
        try {
            sqlite3_busy_timeout(db, 100);
            const string query = "SELECT id,cwd,COALESCE(NULLIF(TRIM(custom_title),''),title,''),status,MAX(updated_at,COALESCE(last_activity_at,0)),model FROM sessions WHERE deleted_at IS NULL AND LOWER(status) != 'archived' ORDER BY 5 DESC LIMIT 500";
            var rows = new List<BuddyRow>(); IntPtr stmt = Prepare(db, query);
            try {
                int rc; while ((rc = sqlite3_step(stmt)) == 100) {
                    string id = Text(stmt,0); Guid guid; double timestamp = sqlite3_column_double(stmt,4) / 1000.0;
                    if (!Guid.TryParse(id, out guid) || double.IsNaN(timestamp) || timestamp <= since || timestamp > DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 300) continue;
                    rows.Add(new BuddyRow { Id=id, Project=Text(stmt,1), Title=Text(stmt,2), Status=Text(stmt,3), Updated=timestamp, Model=Text(stmt,5) });
                }
                if (rc != 101) throw new InvalidOperationException("WorkBuddy database read failed");
            } finally { sqlite3_finalize(stmt); }
            return rows.ToArray();
        } finally { sqlite3_close(db); }
    }
    public static Row[] Read(string path, double since) {
        IntPtr db; int result = sqlite3_open_v2(Utf8(path), out db, 1 | 0x8000, IntPtr.Zero);
        if (result != 0) { if (db != IntPtr.Zero) sqlite3_close(db); throw new InvalidOperationException("Work catalog unavailable"); }
        try {
            sqlite3_busy_timeout(db, 100);
            var columns = new HashSet<string>(); IntPtr schema = Prepare(db, "PRAGMA table_info(local_thread_catalog)");
            try { int rc; while ((rc = sqlite3_step(schema)) == 100) columns.Add(Text(schema, 1)); if (rc != 101) throw new InvalidOperationException("Work catalog schema unavailable"); } finally { sqlite3_finalize(schema); }
            foreach (string name in new[] { "host_id", "thread_id", "display_title", "source_kind", "source_updated_at", "conversation_origin" }) if (!columns.Contains(name)) throw new InvalidOperationException("Work catalog schema unsupported");
            string status = columns.Contains("chatgpt_async_status") ? "chatgpt_async_status" : "NULL";
            string recency = columns.Contains("source_recency_at") ? "COALESCE(source_recency_at,0)" : "0";
            string present = columns.Contains("missing_candidate") ? " AND missing_candidate = 0" : "";
            string query = "SELECT host_id,thread_id,display_title,MAX(source_updated_at," + recency + ")," + status + " FROM local_thread_catalog WHERE source_kind='chatgpt' AND conversation_origin IN ('tpp','flora')" + present + " ORDER BY 4 DESC LIMIT 500";
            var rows = new List<Row>(); IntPtr stmt = Prepare(db, query);
            try {
                int rc; while ((rc = sqlite3_step(stmt)) == 100) {
                    string host = Text(stmt,0), id = Text(stmt,1); double timestamp = sqlite3_column_double(stmt,3); Guid guid;
                    if (host == null || !host.StartsWith("chatgpt:", StringComparison.Ordinal) || !Guid.TryParse(id, out guid) || timestamp <= since || timestamp > DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 300) continue;
                    rows.Add(new Row { Host=host, Id=id, Title=Text(stmt,2), Updated=timestamp, Status=sqlite3_column_type(stmt,4) == 5 ? (int?)null : sqlite3_column_int(stmt,4) });
                }
                if (rc != 101) throw new InvalidOperationException("Work catalog read failed");
            } finally { sqlite3_finalize(stmt); }
            return rows.ToArray();
        } finally { sqlite3_close(db); }
    }
}
