namespace AELanguageSwitcher.Core;

public enum AELocale
{
    EnglishUS,
    SimplifiedChinese
}

public enum EffectiveLanguage
{
    English,
    SimplifiedChinese,
    SystemDefault,
    Unknown
}

public enum TargetLanguage
{
    English,
    SimplifiedChinese
}

public enum ChineseEligibility
{
    Available,
    MissingResource,
    SystemLanguageNotSimplifiedChinese
}

public sealed record AEInstallation(
    string DisplayName,
    string Version,
    string ExecutablePath,
    IReadOnlySet<AELocale> AvailableLocales)
{
    public string Id => ExecutablePath;
}

public sealed record LanguageState(
    EffectiveLanguage Effective,
    ChineseEligibility ChineseEligibility,
    bool MarkerExists,
    string PreferredLanguage);

public sealed class SemanticVersionComparer : IComparer<string>
{
    public static SemanticVersionComparer Descending { get; } = new(descending: true);

    private readonly bool _descending;

    public SemanticVersionComparer(bool descending = false)
    {
        _descending = descending;
    }

    public int Compare(string? left, string? right)
    {
        var result = CompareAscending(left ?? string.Empty, right ?? string.Empty);
        return _descending ? -result : result;
    }

    private static int CompareAscending(string left, string right)
    {
        var leftParts = Parse(left);
        var rightParts = Parse(right);
        var count = Math.Max(leftParts.Length, rightParts.Length);
        for (var index = 0; index < count; index++)
        {
            var leftPart = index < leftParts.Length ? leftParts[index] : 0;
            var rightPart = index < rightParts.Length ? rightParts[index] : 0;
            var comparison = leftPart.CompareTo(rightPart);
            if (comparison != 0)
            {
                return comparison;
            }
        }
        return 0;
    }

    private static int[] Parse(string version) => version
        .Split('.', StringSplitOptions.RemoveEmptyEntries)
        .Select(component => int.TryParse(component, out var value) ? value : 0)
        .ToArray();
}

