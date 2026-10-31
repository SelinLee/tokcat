using System;
using System.Collections.Generic;
using System.Management;
using System.Text.RegularExpressions;
using System.Threading;

// WMI can take several seconds; sampling must never block the window thread.
public sealed class TokcatGpuMetrics {
    readonly object gate = new object();
    readonly ManualResetEvent stop = new ManualResetEvent(false);
    double? latest;
    DateTime sampledAt;

    public static Dictionary<string, double> Rates(IDictionary<string, ulong[]> previous, IDictionary<string, ulong[]> current) {
        var rates = new Dictionary<string, double>();
        foreach (var entry in current) {
            ulong[] old, next = entry.Value;
            if (next == null || next.Length != 2 || !previous.TryGetValue(entry.Key, out old) || old == null || old.Length != 2 || next[0] < old[0] || next[1] <= old[1]) continue;
            rates[entry.Key] = 100.0 * (next[0] - old[0]) / (next[1] - old[1]);
        }
        return rates;
    }

    public static double? BusiestEngine(IDictionary<string, double> counters) {
        var engines = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in counters) {
            var match = Regex.Match(entry.Key, @"^pid_\d+_(luid_.*_phys_\d+_eng_\d+)_engtype_", RegexOptions.IgnoreCase);
            if (!match.Success || double.IsNaN(entry.Value) || double.IsInfinity(entry.Value) || entry.Value < 0) continue;
            double total;
            engines.TryGetValue(match.Groups[1].Value, out total);
            engines[match.Groups[1].Value] = total + entry.Value;
        }
        double? maximum = null;
        foreach (double value in engines.Values) maximum = Math.Max(maximum ?? 0, Math.Min(100, value));
        return maximum;
    }

    public void Start() {
        var thread = new Thread(Loop); thread.IsBackground = true; thread.Name = "tokcat GPU sampler"; thread.Start();
    }
    public void Stop() { stop.Set(); }
    public double? Read() {
        lock (gate) return (DateTime.UtcNow - sampledAt).TotalSeconds <= 30 ? latest : null;
    }
    void Loop() {
        Dictionary<string, ulong[]> previous = null;
        try {
            do {
                double? value = null;
                try {
                    var counters = new Dictionary<string, ulong[]>();
                    using (var query = new ManagementObjectSearcher("SELECT Name, UtilizationPercentage, Timestamp_Sys100NS FROM Win32_PerfRawData_GPUPerformanceCounters_GPUEngine"))
                    using (var rows = query.Get()) {
                        foreach (ManagementObject row in rows) {
                            using (row) {
                                var name = row["Name"] as string;
                                if (name != null && row["UtilizationPercentage"] != null && row["Timestamp_Sys100NS"] != null)
                                    counters[name] = new ulong[] { Convert.ToUInt64(row["UtilizationPercentage"]), Convert.ToUInt64(row["Timestamp_Sys100NS"]) };
                            }
                        }
                    }
                    if (previous != null) value = BusiestEngine(Rates(previous, counters));
                    previous = counters;
                } catch (Exception) { previous = null; /* Counters are optional and may be unavailable. */ }
                lock (gate) { latest = value; sampledAt = DateTime.UtcNow; }
            } while (!stop.WaitOne(TimeSpan.FromSeconds(10)));
        } finally { stop.Dispose(); }
    }
}
