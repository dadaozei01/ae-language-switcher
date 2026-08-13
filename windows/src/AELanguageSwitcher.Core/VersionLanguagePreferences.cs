using System.Text;
using System.Text.RegularExpressions;

namespace AELanguageSwitcher.Core;

public sealed class PreferenceFormatException(string message) : Exception(message);

public sealed record TextFileFormat(Encoding Encoding, bool HasBom, string NewLine);

public sealed record ParsedDebugDatabase(
    string Language,
    EffectiveLanguage Effective,
    TextFileFormat Format,
    IReadOnlyList<string> Lines,
    int LanguageLineIndex);

public sealed record VersionLanguageState(
    EffectiveLanguage Effective,
    string RawLanguage,
    string DatabasePath,
    bool IsFallback);

public sealed class VersionLanguagePreferenceLocator(string preferencesRoot)
{
    private static readonly Regex VersionPattern = new(@"^(?<major>\d+)\.(?<minor>\d+)", RegexOptions.CultureInvariant);

    public string GetDatabasePath(AEInstallation installation)
    {
        var match = VersionPattern.Match(installation.Version);
        if (!match.Success)
        {
            throw new ArgumentException("After Effects 版本号缺少有效的主版本和次版本。", nameof(installation));
        }

        return Path.Combine(preferencesRoot, $"{match.Groups["major"].Value}.{match.Groups["minor"].Value}", "Debug Database.txt");
    }
}

public static class DebugDatabaseParser
{
    public static ParsedDebugDatabase Parse(byte[] bytes)
    {
        var hasBom = bytes.AsSpan().StartsWith(Encoding.UTF8.Preamble);
        var offset = hasBom ? Encoding.UTF8.Preamble.Length : 0;
        var text = Encoding.UTF8.GetString(bytes, offset, bytes.Length - offset);
        var newLine = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var lines = text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
        var matches = lines
            .Select((line, index) => (line, index, columns: line.Split('\t')))
            .Where(item => item.columns.Length > 0 && item.columns[0] == "ApplicationLanguage")
            .ToArray();

        if (matches.Length != 1 || matches[0].columns.Length < 3)
        {
            throw new PreferenceFormatException("ApplicationLanguage 项缺失、重复或格式异常。");
        }

        var language = matches[0].columns[1];
        var effective = language switch
        {
            "en_US" => EffectiveLanguage.English,
            "zh_CN" => EffectiveLanguage.SimplifiedChinese,
            _ => EffectiveLanguage.Unknown
        };
        return new ParsedDebugDatabase(
            language,
            effective,
            new TextFileFormat(new UTF8Encoding(hasBom), hasBom, newLine),
            lines,
            matches[0].index);
    }
}

public interface IProductLanguageHistory
{
    string? GetLatest(string productVersion);
}

public interface IVersionLanguageDetector
{
    VersionLanguageState Detect(AEInstallation installation);
}

public sealed class VersionLanguageDetector(
    VersionLanguagePreferenceLocator locator,
    IProductLanguageHistory history) : IVersionLanguageDetector
{
    public VersionLanguageState Detect(AEInstallation installation)
    {
        var path = locator.GetDatabasePath(installation);
        if (!File.Exists(path))
        {
            return new VersionLanguageState(EffectiveLanguage.Unknown, string.Empty, path, false);
        }

        var parsed = DebugDatabaseParser.Parse(File.ReadAllBytes(path));
        if (parsed.Effective != EffectiveLanguage.Unknown || !string.IsNullOrEmpty(parsed.Language))
        {
            return new VersionLanguageState(parsed.Effective, parsed.Language, path, false);
        }

        var fallback = history.GetLatest(installation.Version) ?? string.Empty;
        return new VersionLanguageState(ToEffective(fallback), fallback, path, !string.IsNullOrEmpty(fallback));
    }

    internal static EffectiveLanguage ToEffective(string language) => language switch
    {
        "en_US" => EffectiveLanguage.English,
        "zh_CN" => EffectiveLanguage.SimplifiedChinese,
        _ => EffectiveLanguage.Unknown
    };
}

public sealed class CcxProductLanguageHistory(string ccxRoot) : IProductLanguageHistory
{
    public string? GetLatest(string productVersion)
    {
        var match = Regex.Match(productVersion, @"^(\d+)\.(\d+)");
        if (!match.Success || !Directory.Exists(ccxRoot)) return null;
        var prefix = $"AEFT-{match.Groups[1].Value}-{match.Groups[2].Value}-";
        return Directory.EnumerateFiles(ccxRoot, $"{prefix}*.json", SearchOption.AllDirectories)
            .Select(path => new { path, name = Path.GetFileName(path) })
            .Select(item => new { item.path, match = Regex.Match(item.name, $@"^{Regex.Escape(prefix)}(?<locale>[a-z]{{2}}_[A-Z]{{2}})-") })
            .Where(item => item.match.Success)
            .OrderByDescending(item => File.GetLastWriteTimeUtc(item.path))
            .Select(item => item.match.Groups["locale"].Value)
            .FirstOrDefault();
    }
}
