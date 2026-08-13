using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;

namespace AELanguageSwitcher.Core;

public interface IUserDialog
{
    void Show(string title, string message);
}

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly IInstallationScanner _scanner;
    private readonly ILanguageStateDetector _detector;
    private readonly IAfterEffectsProcessMonitor _processMonitor;
    private readonly ILanguageSwitcher _switcher;
    private readonly IUserDialog _dialog;
    private readonly IVersionLanguageDetector? _versionDetector;
    private readonly IVersionLanguageSwitcher? _versionSwitcher;
    private IReadOnlyList<AEInstallation> _installations = Array.Empty<AEInstallation>();
    private VersionLanguageState? _versionLanguageState;
    private LanguageState? _languageState;
    private AEInstallation? _selectedInstallation;
    private string _statusMessage = "正在扫描…";
    private bool _isBusy;

    public MainViewModel(
        IInstallationScanner scanner,
        ILanguageStateDetector detector,
        IAfterEffectsProcessMonitor processMonitor,
        ILanguageSwitcher switcher,
        IUserDialog dialog)
    {
        _scanner = scanner;
        _detector = detector;
        _processMonitor = processMonitor;
        _switcher = switcher;
        _dialog = dialog;
        RefreshCommand = new RelayCommand(Refresh, () => !IsBusy);
        SwitchCommand = new RelayCommand(RequestSwitch, () => CanSwitch);
        SwitchToChineseCommand = new RelayCommand(() => RequestVersionSwitch(TargetLanguage.SimplifiedChinese), () => CanSwitchToChinese);
        SwitchToEnglishCommand = new RelayCommand(() => RequestVersionSwitch(TargetLanguage.English), () => CanSwitchToEnglish);
    }

    public MainViewModel(
        IInstallationScanner scanner,
        IVersionLanguageDetector detector,
        IAfterEffectsProcessMonitor processMonitor,
        IVersionLanguageSwitcher switcher,
        IUserDialog dialog)
        : this(scanner, new UnusedDetector(), processMonitor, new UnusedSwitcher(), dialog)
    {
        _versionDetector = detector;
        _versionSwitcher = switcher;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ICommand RefreshCommand { get; }
    public ICommand SwitchCommand { get; }
    public ICommand SwitchToChineseCommand { get; }
    public ICommand SwitchToEnglishCommand { get; }
    public IReadOnlyList<AEInstallation> Installations
    {
        get => _installations;
        private set => SetField(ref _installations, value);
    }

    public AEInstallation? SelectedInstallation
    {
        get => _selectedInstallation;
        set
        {
            if (SetField(ref _selectedInstallation, value) && _versionDetector is not null)
            {
                _versionLanguageState = value is null ? null : _versionDetector.Detect(value);
                NotifyDerivedState();
            }
        }
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            if (SetField(ref _isBusy, value))
            {
                NotifyDerivedState();
            }
        }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => SetField(ref _statusMessage, value);
    }

    public string LanguageLabel => _languageState?.Effective switch
    {
        EffectiveLanguage.English => "中文  |  ● English",
        EffectiveLanguage.SimplifiedChinese => "● 中文  |  English",
        _ => "中文  |  English"
    };

    public string PrimaryButtonText => PrimaryTarget switch
    {
        TargetLanguage.English => "切换到 English",
        TargetLanguage.SimplifiedChinese => "切换到中文",
        _ when SelectedInstallation is null => "未检测到 After Effects",
        _ => "无法确定当前语言"
    };

    public bool CanSwitch => !IsBusy && PrimaryTarget is not null &&
        (PrimaryTarget != TargetLanguage.SimplifiedChinese
         || _languageState?.ChineseEligibility == ChineseEligibility.Available);

    public bool CanSwitchToChinese => _versionDetector is not null && !IsBusy && SelectedInstallation is not null
        && SelectedInstallation.AvailableLocales.Contains(AELocale.SimplifiedChinese)
        && _versionLanguageState?.Effective != EffectiveLanguage.SimplifiedChinese;
    public bool CanSwitchToEnglish => _versionDetector is not null && !IsBusy && SelectedInstallation is not null
        && SelectedInstallation.AvailableLocales.Contains(AELocale.EnglishUS)
        && _versionLanguageState?.Effective != EffectiveLanguage.English;
    public string SelectedVersionLabel => SelectedInstallation is null ? "未检测到 After Effects" : $"{SelectedInstallation.DisplayName}（{SelectedInstallation.Version}）";
    public string InstallationPath => SelectedInstallation?.ExecutablePath ?? string.Empty;
    public string ResourceStatus => SelectedInstallation is null ? string.Empty :
        $"中文资源：{(SelectedInstallation.AvailableLocales.Contains(AELocale.SimplifiedChinese) ? "可用" : "缺失")}　English：{(SelectedInstallation.AvailableLocales.Contains(AELocale.EnglishUS) ? "可用" : "缺失")}";
    public string VersionLanguageLabel => _versionLanguageState?.Effective switch
    {
        EffectiveLanguage.English => "当前设置：English",
        EffectiveLanguage.SimplifiedChinese => "当前设置：简体中文",
        _ => "当前设置：未设置"
    };

    private TargetLanguage? PrimaryTarget => _languageState?.Effective switch
    {
        EffectiveLanguage.SimplifiedChinese => TargetLanguage.English,
        EffectiveLanguage.English => TargetLanguage.SimplifiedChinese,
        _ => null
    };

    public void Refresh()
    {
        if (IsBusy)
        {
            return;
        }

        IsBusy = true;
        try
        {
            var previousPath = SelectedInstallation?.ExecutablePath;
            var installations = _scanner.Scan();
            if (_versionDetector is not null)
            {
                Installations = installations;
                SelectedInstallation = installations.FirstOrDefault(item =>
                    string.Equals(item.ExecutablePath, previousPath, StringComparison.OrdinalIgnoreCase))
                    ?? installations.FirstOrDefault();
                StatusMessage = SelectedInstallation is null ? "未检测到 After Effects。" : $"已检测到 {installations.Count} 个 After Effects 版本。";
                NotifyDerivedState();
                return;
            }
            SelectedInstallation = installations.FirstOrDefault();
            _languageState = SelectedInstallation is null ? null : _detector.Detect(SelectedInstallation);
            StatusMessage = BuildReadyStatus();
            NotifyDerivedState();
        }
        catch (Exception error)
        {
            SelectedInstallation = null;
            _languageState = null;
            StatusMessage = $"扫描失败：{error.Message}";
            _dialog.Show("扫描失败", StatusMessage);
            NotifyDerivedState();
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void RequestVersionSwitch(TargetLanguage target)
    {
        if (_versionSwitcher is null || SelectedInstallation is null || IsBusy) return;
        if (_processMonitor.IsRunning())
        {
            _dialog.Show("After Effects 正在运行", "请先退出所有正在运行的 After Effects，再修改语言。");
            return;
        }
        IsBusy = true;
        try
        {
            _versionLanguageState = _versionSwitcher.Switch(SelectedInstallation, target);
            StatusMessage = $"After Effects {SelectedInstallation.Version} 已设置为 {(target == TargetLanguage.English ? "English" : "简体中文")}，重启该版本后生效。";
            NotifyDerivedState();
        }
        catch (Exception error)
        {
            StatusMessage = error.Message;
            _dialog.Show("语言切换失败", error.Message);
        }
        finally { IsBusy = false; }
    }

    public void RequestSwitch()
    {
        if (!CanSwitch || PrimaryTarget is not { } target || _languageState is null)
        {
            return;
        }

        IsBusy = true;
        try
        {
            if (_processMonitor.IsRunning())
            {
                StatusMessage = "请先退出所有正在运行的 After Effects，再切换语言。";
                _dialog.Show("After Effects 正在运行", StatusMessage);
                return;
            }

            _switcher.Switch(target, _languageState.ChineseEligibility);
            var installations = _scanner.Scan();
            SelectedInstallation = installations.FirstOrDefault();
            _languageState = SelectedInstallation is null ? null : _detector.Detect(SelectedInstallation);
            StatusMessage = target == TargetLanguage.English
                ? "已切换到 English。重新启动 After Effects 后生效。"
                : "已切换到简体中文。重新启动 After Effects 后生效。";
            NotifyDerivedState();
        }
        catch (LanguageSwitchException error)
        {
            PresentSwitchError(error);
        }
        catch (Exception error)
        {
            StatusMessage = $"文件操作失败：{error.Message}";
            _dialog.Show("文件操作失败", StatusMessage);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private string BuildReadyStatus()
    {
        if (SelectedInstallation is null || _languageState is null)
        {
            return "未检测到 After Effects。";
        }
        return _languageState.ChineseEligibility switch
        {
            ChineseEligibility.MissingResource => "所选 AE 缺少简体中文资源。",
            ChineseEligibility.SystemLanguageNotSimplifiedChinese =>
                $"Windows 首选语言为 {_languageState.PreferredLanguage}，不是简体中文。",
            _ => $"已检测到 After Effects {SelectedInstallation.Version}。"
        };
    }

    private void PresentSwitchError(LanguageSwitchException error)
    {
        var title = error.Code switch
        {
            LanguageSwitchErrorCode.ChineseUnavailable => "无法切换到简体中文",
            LanguageSwitchErrorCode.UnsafeMarkerType => "语言标记路径不安全",
            LanguageSwitchErrorCode.NonEmptyMarker => "语言标记文件含有内容",
            _ => "文件操作失败"
        };
        StatusMessage = error.Message;
        _dialog.Show(title, error.Message);
    }

    private void NotifyDerivedState()
    {
        OnPropertyChanged(nameof(LanguageLabel));
        OnPropertyChanged(nameof(PrimaryButtonText));
        OnPropertyChanged(nameof(CanSwitch));
        (RefreshCommand as RelayCommand)?.RaiseCanExecuteChanged();
        (SwitchCommand as RelayCommand)?.RaiseCanExecuteChanged();
        (SwitchToChineseCommand as RelayCommand)?.RaiseCanExecuteChanged();
        (SwitchToEnglishCommand as RelayCommand)?.RaiseCanExecuteChanged();
        OnPropertyChanged(nameof(SelectedVersionLabel));
        OnPropertyChanged(nameof(InstallationPath));
        OnPropertyChanged(nameof(ResourceStatus));
        OnPropertyChanged(nameof(VersionLanguageLabel));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

file sealed class UnusedDetector : ILanguageStateDetector
{
    public LanguageState Detect(AEInstallation installation) => throw new NotSupportedException();
}

file sealed class UnusedSwitcher : ILanguageSwitcher
{
    public void Switch(TargetLanguage target, ChineseEligibility chineseEligibility) => throw new NotSupportedException();
}

public sealed class RelayCommand(Action execute, Func<bool>? canExecute = null) : ICommand
{
    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
    public void Execute(object? parameter) => execute();
    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}

