using System;
using System.Runtime.InteropServices;

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
    public sealed class Snapshot { public double? CpuPercent; public double? MemoryPercent; }
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
        return snapshot;
    }
}
