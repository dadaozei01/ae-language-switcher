using System.Diagnostics;
using Microsoft.Win32;

namespace AELanguageSwitcher.Core;

public interface IInstallationScanner
{
    IReadOnlyList<AEInstallation> Scan();
}

public interface IInstallationSource
{
    IEnumerable<string> GetCandidates();
}

public interface IExecutableMetadata
{
    ExecutableMetadata? Read(string executablePath);
}

public interface IResourceProbe
{
    IReadOnlySet<AELocale> Detect(string installationDirectory);
}

public sealed record ExecutableMetadata(string DisplayName, string Version);

public sealed class InstallationScanner(
    IInstallationSource source,
    IExecutableMetadata metadata,
    IResourceProbe resources) : IInstallationScanner
{
    public IReadOnlyList<AEInstallation> Scan()
    {
        var installations = new List<AEInstallation>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var rawCandidate in source.GetCandidates())
        {
            try
            {
                if (string.IsNullOrWhiteSpace(rawCandidate)
                    || rawCandidate.Contains("Render Engine", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var candidate = Path.TrimEndingDirectorySeparator(Path.GetFullPath(rawCandidate));
                var executablePath = ResolveExecutable(candidate);
                if (!seen.Add(executablePath))
                {
                    continue;
                }

                var executableMetadata = metadata.Read(executablePath);
                if (executableMetadata is null
                    || executableMetadata.DisplayName.Contains("Render Engine", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                installations.Add(new AEInstallation(
                    executableMetadata.DisplayName,
                    executableMetadata.Version,
                    executablePath,
                    resources.Detect(Path.GetDirectoryName(Path.GetDirectoryName(executablePath)) ?? candidate)));
            }
            catch (Exception error) when (error is IOException
                or UnauthorizedAccessException
                or ArgumentException
                or NotSupportedException)
            {
                // A damaged or inaccessible candidate must not hide valid installations.
            }
        }

        return installations
            .OrderBy(item => item.Version, SemanticVersionComparer.Descending)
            .ThenBy(item => item.ExecutablePath, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private string ResolveExecutable(string candidate)
    {
        var directExecutable = Path.Combine(candidate, "AfterFX.exe");
        if (metadata.Read(directExecutable) is not null)
        {
            return directExecutable;
        }
        return Path.Combine(candidate, "Support Files", "AfterFX.exe");
    }
}

public sealed class WindowsInstallationSource : IInstallationSource
{
    private const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";

    public IEnumerable<string> GetCandidates()
    {
        var candidates = new List<string>();
        if (OperatingSystem.IsWindows())
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                ReadRegistry(view, candidates);
            }
        }

        AddAdobeDirectories(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), candidates);
        AddAdobeDirectories(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), candidates);
        return candidates;
    }

    private static void ReadRegistry(RegistryView view, ICollection<string> candidates)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var uninstall = baseKey.OpenSubKey(UninstallKey);
            if (uninstall is null)
            {
                return;
            }

            foreach (var keyName in uninstall.GetSubKeyNames())
            {
                using var key = uninstall.OpenSubKey(keyName);
                var displayName = key?.GetValue("DisplayName") as string;
                var installLocation = key?.GetValue("InstallLocation") as string;
                if (displayName?.StartsWith("Adobe After Effects", StringComparison.OrdinalIgnoreCase) == true
                    && !string.IsNullOrWhiteSpace(installLocation))
                {
                    candidates.Add(installLocation);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            // Program Files fallback remains available.
        }
    }

    private static void AddAdobeDirectories(string programFiles, ICollection<string> candidates)
    {
        if (string.IsNullOrWhiteSpace(programFiles))
        {
            return;
        }

        try
        {
            var adobe = Path.Combine(programFiles, "Adobe");
            foreach (var directory in Directory.EnumerateDirectories(adobe, "Adobe After Effects*", SearchOption.TopDirectoryOnly))
            {
                candidates.Add(directory);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or DirectoryNotFoundException)
        {
            // Missing and inaccessible roots are equivalent to no fallback candidates.
        }
    }
}

public sealed class FileExecutableMetadata : IExecutableMetadata
{
    public ExecutableMetadata? Read(string executablePath)
    {
        if (!File.Exists(executablePath))
        {
            return null;
        }

        var info = FileVersionInfo.GetVersionInfo(executablePath);
        var displayName = string.IsNullOrWhiteSpace(info.ProductName) ? "Adobe After Effects" : info.ProductName;
        var version = string.IsNullOrWhiteSpace(info.ProductVersion)
            ? info.FileVersion
            : info.ProductVersion;
        if (string.IsNullOrWhiteSpace(version))
        {
            return null;
        }

        var normalizedVersion = new string(version.TakeWhile(character => char.IsDigit(character) || character == '.').ToArray());
        return string.IsNullOrWhiteSpace(normalizedVersion)
            ? null
            : new ExecutableMetadata(displayName, normalizedVersion.TrimEnd('.'));
    }
}

public sealed class WindowsResourceProbe : IResourceProbe
{
    public IReadOnlySet<AELocale> Detect(string installationDirectory)
    {
        var result = new HashSet<AELocale>();
        var supportFiles = Path.Combine(installationDirectory, "Support Files");
        var roots = new[]
        {
            supportFiles,
            Path.Combine(supportFiles, "Dictionaries"),
            Path.Combine(supportFiles, "AMT"),
            Path.Combine(supportFiles, "Resources"),
            Path.Combine(supportFiles, "zdictionaries")
        };

        if (ContainsLocale(roots, "zh_CN"))
        {
            result.Add(AELocale.SimplifiedChinese);
        }
        if (ContainsLocale(roots, "en_US"))
        {
            result.Add(AELocale.EnglishUS);
        }
        return result;
    }

    private static bool ContainsLocale(IEnumerable<string> roots, string locale)
    {
        foreach (var root in roots)
        {
            try
            {
                if (Directory.Exists(Path.Combine(root, locale))
                    || Directory.EnumerateFileSystemEntries(root, $"*{locale}*", SearchOption.TopDirectoryOnly).Any())
                {
                    return true;
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or DirectoryNotFoundException)
            {
                // Try the next known resource root.
            }
        }
        return false;
    }
}
