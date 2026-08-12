using AELanguageSwitcher.Core;

namespace AELanguageSwitcher.Core.Tests;

[TestClass]
public sealed class MainViewModelTests
{
    [TestMethod]
    public void RefreshSelectsHighestInstallationAndTargetsEnglish()
    {
        var newest = Installation("26.0");
        var older = Installation("25.0");
        var model = MakeModel(
            new ScannerFake(newest, older),
            new DetectorFake(State(EffectiveLanguage.SimplifiedChinese)));

        model.Refresh();

        Assert.AreEqual(newest, model.SelectedInstallation);
        Assert.AreEqual("切换到 English", model.PrimaryButtonText);
        Assert.IsTrue(model.CanSwitch);
    }

    [TestMethod]
    public void NoInstallationDisablesSwitching()
    {
        var model = MakeModel(new ScannerFake(), new DetectorFake(State(EffectiveLanguage.SimplifiedChinese)));
        model.Refresh();
        Assert.AreEqual("未检测到 After Effects", model.PrimaryButtonText);
        Assert.IsFalse(model.CanSwitch);
    }

    [TestMethod]
    public void RunningAfterEffectsBlocksMutation()
    {
        var switcher = new SwitcherFake();
        var dialog = new DialogFake();
        var model = MakeModel(
            new ScannerFake(Installation("26.0")),
            new DetectorFake(State(EffectiveLanguage.SimplifiedChinese)),
            new ProcessMonitorFake(true),
            switcher,
            dialog);
        model.Refresh();

        model.RequestSwitch();

        Assert.AreEqual(0, switcher.CallCount);
        Assert.AreEqual("After Effects 正在运行", dialog.LastTitle);
    }

    [TestMethod]
    public void SuccessfulSwitchRefreshesState()
    {
        var switcher = new SwitcherFake();
        var detector = new DetectorFake(
            State(EffectiveLanguage.SimplifiedChinese),
            State(EffectiveLanguage.English));
        var model = MakeModel(new ScannerFake(Installation("26.0")), detector, switcher: switcher);
        model.Refresh();

        model.RequestSwitch();

        Assert.AreEqual(1, switcher.CallCount);
        Assert.AreEqual(TargetLanguage.English, switcher.LastTarget);
        Assert.AreEqual("已切换到 English。重新启动 After Effects 后生效。", model.StatusMessage);
    }

    private static MainViewModel MakeModel(
        IInstallationScanner scanner,
        ILanguageStateDetector detector,
        IAfterEffectsProcessMonitor? monitor = null,
        ILanguageSwitcher? switcher = null,
        IUserDialog? dialog = null) => new(
            scanner,
            detector,
            monitor ?? new ProcessMonitorFake(false),
            switcher ?? new SwitcherFake(),
            dialog ?? new DialogFake());

    private static AEInstallation Installation(string version) => new(
        "After Effects",
        version,
        $@"C:\AE{version}\Support Files\AfterFX.exe",
        new HashSet<AELocale> { AELocale.EnglishUS, AELocale.SimplifiedChinese });

    private static LanguageState State(EffectiveLanguage language) => new(
        language,
        ChineseEligibility.Available,
        language == EffectiveLanguage.English,
        "zh-CN");
}

internal sealed class ScannerFake(params AEInstallation[] installations) : IInstallationScanner
{
    public IReadOnlyList<AEInstallation> Scan() => installations;
}

internal sealed class DetectorFake(params LanguageState[] states) : ILanguageStateDetector
{
    private int _index;
    public LanguageState Detect(AEInstallation installation)
    {
        var result = states[Math.Min(_index, states.Length - 1)];
        _index++;
        return result;
    }
}

internal sealed class ProcessMonitorFake(bool isRunning) : IAfterEffectsProcessMonitor
{
    public bool IsRunning() => isRunning;
}

internal sealed class SwitcherFake : ILanguageSwitcher
{
    public int CallCount { get; private set; }
    public TargetLanguage? LastTarget { get; private set; }
    public LanguageSwitchException? Error { get; init; }

    public void Switch(TargetLanguage target, ChineseEligibility chineseEligibility)
    {
        CallCount++;
        LastTarget = target;
        if (Error is not null)
        {
            throw Error;
        }
    }
}

internal sealed class DialogFake : IUserDialog
{
    public string? LastTitle { get; private set; }
    public string? LastMessage { get; private set; }
    public void Show(string title, string message)
    {
        LastTitle = title;
        LastMessage = message;
    }
}

