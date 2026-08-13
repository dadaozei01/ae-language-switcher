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
