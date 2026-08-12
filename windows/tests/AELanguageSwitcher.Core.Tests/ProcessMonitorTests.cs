using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class ProcessMonitorTests
{
    [DataTestMethod]
    [DataRow("AfterFX", true)]
    [DataRow("afterfx", true)]
    [DataRow("aerender", false)]
    [DataRow("Adobe Premiere Pro", false)]
    [DataRow("Photoshop", false)]
    public void OnlyAfterFxBlocksSwitching(string processName, bool expected)
    {
        var monitor = new AfterEffectsProcessMonitor(new ProcessSnapshotFake(processName));
        Assert.AreEqual(expected, monitor.IsRunning());
    }
}

internal sealed class ProcessSnapshotFake(params string[] names) : IProcessSnapshot
{
    public IEnumerable<string> GetProcessNames() => names;
}

