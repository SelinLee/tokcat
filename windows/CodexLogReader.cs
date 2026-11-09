using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

// Stream complete JSONL records with bounded memory, even if a tool emits a
// very large output. The snapshot boundary avoids parsing a partial write.
public static class TokcatCodexLogReader {
    public static IEnumerable<string> Read(string path) {
        const int maxLineBytes = 2 * 1024 * 1024;
        using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var line = new MemoryStream()) {
            long remaining = file.Length;
            var buffer = new byte[16384];
            bool skip = false;
            while (remaining > 0) {
                int read = file.Read(buffer, 0, (int)Math.Min(buffer.Length, remaining));
                if (read == 0) break;
                remaining -= read;
                for (int i = 0; i < read; i++) {
                    byte b = buffer[i];
                    if (b == 10) {
                        if (!skip && line.Length > 0) yield return Encoding.UTF8.GetString(line.GetBuffer(), 0, (int)line.Length);
                        line.SetLength(0); skip = false;
                    } else if (!skip) {
                        if (line.Length >= maxLineBytes) { line.SetLength(0); skip = true; }
                        else line.WriteByte(b);
                    }
                }
            }
        }
    }
}
