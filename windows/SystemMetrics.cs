using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

// Per-interface baselines prevent a newly attached or reset adapter from
// appearing as a burst of lifetime traffic.
public sealed class TokcatNetworkRateSampler {
    Dictionary<string, long[]> previous;
    double previousTime;
    public sealed class Rate { public double Down, Up; }
    public Rate Observe(Dictionary<string, long[]> counters, double time) {
        if (counters == null || double.IsNaN(time) || double.IsInfinity(time)) { previous = null; return null; }
        if (previous == null) { previous = counters; previousTime = time; return null; }
        double elapsed = time - previousTime;
        if (elapsed <= 0) return null;
        var rate = new Rate();
        foreach (var entry in counters) {
            long[] old, current = entry.Value;
            if (current == null || current.Length != 2 || !previous.TryGetValue(entry.Key, out old) || old == null || old.Length != 2 || current[0] < old[0] || current[1] < old[1]) continue;
            rate.Down += (current[0] - old[0]) / elapsed;
            rate.Up += (current[1] - old[1]) / elapsed;
        }
        previous = counters; previousTime = time;
        return rate;
    }
}

public static class TokcatSystemMetrics {
    [StructLayout(LayoutKind.Sequential)]
    struct FileTime { public uint Low, High; public ulong Value { get { return ((ulong)High << 32) | Low; } } }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
    sealed class MemoryStatus {
        public uint Length, MemoryLoad;
        public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual;
        public MemoryStatus() { Length = (uint)Marshal.SizeOf(typeof(MemoryStatus)); }
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx([In, Out] MemoryStatus buffer);
    static ulong previousIdle, previousKernel, previousUser;
    static bool havePrevious;
    static readonly TokcatNetworkRateSampler networkSampler = new TokcatNetworkRateSampler();
    public sealed class Snapshot { public double? CpuPercent; public double? MemoryPercent; public double? NetworkDown; public double? NetworkUp; }
    public static Snapshot Sample() {
        var snapshot = new Snapshot();
        var memory = new MemoryStatus();
        if (GlobalMemoryStatusEx(memory) && memory.TotalPhys > 0)
            snapshot.MemoryPercent = 100.0 * (memory.TotalPhys - memory.AvailPhys) / memory.TotalPhys;
        FileTime idle, kernel, user;
        if (GetSystemTimes(out idle, out kernel, out user)) {
            ulong i = idle.Value, k = kernel.Value, u = user.Value;
            if (havePrevious && i >= previousIdle && k >= previousKernel && u >= previousUser) {
                ulong deltaIdle = i - previousIdle, total = (k - previousKernel) + (u - previousUser);
                if (total > 0 && deltaIdle <= total) snapshot.CpuPercent = 100.0 * (total - deltaIdle) / total;
            }
            previousIdle = i; previousKernel = k; previousUser = u; havePrevious = true;
        }
        try {
            var counters = new Dictionary<string, long[]>();
            foreach (NetworkInterface adapter in NetworkInterface.GetAllNetworkInterfaces()) {
                if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var stats = adapter.GetIPStatistics();
                counters[adapter.Id] = new long[] { stats.BytesReceived, stats.BytesSent };
            }
            var rate = networkSampler.Observe(counters, (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency);
            if (rate != null) { snapshot.NetworkDown = rate.Down; snapshot.NetworkUp = rate.Up; }
        } catch (NetworkInformationException) { networkSampler.Observe(null, 0); }
          catch (NotSupportedException) { networkSampler.Observe(null, 0); }
          catch (UnauthorizedAccessException) { networkSampler.Observe(null, 0); }
        return snapshot;
    }
}
