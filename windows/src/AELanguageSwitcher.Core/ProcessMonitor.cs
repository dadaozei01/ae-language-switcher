using System.Diagnostics;

namespace AELanguageSwitcher.Core;

public interface IAfterEffectsProcessMonitor
{
    bool IsRunning();
}

public interface IProcessSnapshot
{
    IEnumerable<string> GetProcessNames();
}

public sealed class AfterEffectsProcessMonitor(IProcessSnapshot snapshot) : IAfterEffectsProcessMonitor
{
    public bool IsRunning() => snapshot.GetProcessNames()
        .Any(name => name.Equals("AfterFX", StringComparison.OrdinalIgnoreCase));
}

public sealed class WindowsProcessSnapshot : IProcessSnapshot
{
    public IEnumerable<string> GetProcessNames()
    {
        var names = new List<string>();
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    names.Add(process.ProcessName);
                }
                catch (InvalidOperationException)
                {
                    // The process exited while the snapshot was being collected.
                }
            }
        }
        return names;
    }
}

