namespace AELanguageSwitcher.Core;

public interface ILegacyMarkerTransaction : IDisposable
{
    void Commit();
}

public sealed class LegacyMarkerMigrator(string markerPath)
{
    public ILegacyMarkerTransaction Prepare()
    {
        if (!File.Exists(markerPath) && !Directory.Exists(markerPath)) return new MarkerTransaction(null, null);
        var attributes = File.GetAttributes(markerPath);
        if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
            throw new LanguageSwitchException(LanguageSwitchErrorCode.UnsafeMarkerType, "全局语言标记不是安全的普通文件。");
        if (new FileInfo(markerPath).Length != 0)
            throw new LanguageSwitchException(LanguageSwitchErrorCode.NonEmptyMarker, "全局语言标记包含内容，未做修改。");
        var quarantine = Path.Combine(Path.GetDirectoryName(markerPath)!, $".ae-language-switcher-{Guid.NewGuid():N}.quarantine");
        File.Move(markerPath, quarantine);
        return new MarkerTransaction(markerPath, quarantine);
    }

    private sealed class MarkerTransaction(string? original, string? quarantine) : ILegacyMarkerTransaction
    {
        private bool _committed;
        public void Commit() => _committed = true;
        public void Dispose()
        {
            if (!_committed && original is not null && quarantine is not null && File.Exists(quarantine) && !File.Exists(original))
                File.Move(quarantine, original);
        }
    }
}

public enum LanguageSwitchErrorCode
{
    ChineseUnavailable,
    UnsafeMarkerType,
    NonEmptyMarker,
    FileOperation
}

public sealed class LanguageSwitchException(
    LanguageSwitchErrorCode code,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public LanguageSwitchErrorCode Code { get; } = code;
}

public interface ILanguageSwitcher
{
    void Switch(TargetLanguage target, ChineseEligibility chineseEligibility);
}

public sealed class MarkerSwitcher : ILanguageSwitcher
{
    private readonly string _markerPath;
    private readonly Action _beforeQuarantineMove;

    public MarkerSwitcher(string markerPath, Action? beforeQuarantineMove = null)
    {
        _markerPath = markerPath;
        _beforeQuarantineMove = beforeQuarantineMove ?? (() => { });
    }

    public void Switch(TargetLanguage target, ChineseEligibility chineseEligibility)
    {
        try
        {
            if (target == TargetLanguage.English)
            {
                EnableEnglish();
            }
            else
            {
                EnableSimplifiedChinese(chineseEligibility);
            }
        }
        catch (LanguageSwitchException)
        {
            throw;
        }
        catch (Exception error) when (error is IOException
            or UnauthorizedAccessException
            or ArgumentException
            or NotSupportedException)
        {
            throw new LanguageSwitchException(
                LanguageSwitchErrorCode.FileOperation,
                error.Message,
                error);
        }
    }

    private void EnableEnglish()
    {
        for (var attempt = 0; attempt < 16; attempt++)
        {
            switch (Inspect(_markerPath))
            {
                case MarkerKind.Regular:
                    return;
                case MarkerKind.Unsafe:
                    throw UnsafeMarker();
                case MarkerKind.Absent:
                    try
                    {
                        using var stream = new FileStream(
                            _markerPath,
                            FileMode.CreateNew,
                            FileAccess.Write,
                            FileShare.None);
                        return;
                    }
                    catch (IOException) when (PathExists(_markerPath))
                    {
                        continue;
                    }
            }
        }

        throw new LanguageSwitchException(
            LanguageSwitchErrorCode.FileOperation,
            "语言标记持续发生变化，未做任何修改。");
    }

    private void EnableSimplifiedChinese(ChineseEligibility eligibility)
    {
        if (eligibility != ChineseEligibility.Available)
        {
            throw new LanguageSwitchException(
                LanguageSwitchErrorCode.ChineseUnavailable,
                "当前系统或 After Effects 不满足简体中文切换条件。");
        }

        var kind = Inspect(_markerPath);
        if (kind == MarkerKind.Absent)
        {
            return;
        }
        if (kind == MarkerKind.Unsafe)
        {
            throw UnsafeMarker();
        }
        if (new FileInfo(_markerPath).Length != 0)
        {
            throw NonEmptyMarker();
        }

        _beforeQuarantineMove();
        var quarantinePath = Path.Combine(
            Path.GetDirectoryName(_markerPath) ?? throw new InvalidOperationException("Marker parent is missing."),
            $".ae-language-switcher-{Guid.NewGuid():N}.quarantine");

        try
        {
            File.Move(_markerPath, quarantinePath);
        }
        catch (FileNotFoundException)
        {
            return;
        }

        if (Inspect(quarantinePath) == MarkerKind.Regular && new FileInfo(quarantinePath).Length == 0)
        {
            return;
        }

        RestoreReplacement(quarantinePath);
        throw new LanguageSwitchException(
            LanguageSwitchErrorCode.FileOperation,
            "语言标记在移除前发生变化；替换内容已恢复，未删除任何数据。");
    }

    private void RestoreReplacement(string quarantinePath)
    {
        if (!PathExists(_markerPath))
        {
            File.Move(quarantinePath, _markerPath);
            return;
        }

        throw new LanguageSwitchException(
            LanguageSwitchErrorCode.FileOperation,
            $"语言标记发生变化；替换内容保留在 {quarantinePath}");
    }

    private static MarkerKind Inspect(string path)
    {
        if (!PathExists(path))
        {
            return MarkerKind.Absent;
        }

        var attributes = File.GetAttributes(path);
        if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
        {
            return MarkerKind.Unsafe;
        }
        return MarkerKind.Regular;
    }

    private static bool PathExists(string path) => File.Exists(path) || Directory.Exists(path);

    private static LanguageSwitchException UnsafeMarker() => new(
        LanguageSwitchErrorCode.UnsafeMarkerType,
        "语言标记路径不是安全的普通文件，未做任何修改。");

    private static LanguageSwitchException NonEmptyMarker() => new(
        LanguageSwitchErrorCode.NonEmptyMarker,
        "语言标记文件含有内容，未做任何修改。");

    private enum MarkerKind
    {
        Absent,
        Regular,
        Unsafe
    }
}

