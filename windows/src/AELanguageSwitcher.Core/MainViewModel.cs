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
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ICommand RefreshCommand { get; }
    public ICommand SwitchCommand { get; }

    public AEInstallation? SelectedInstallation
    {
        get => _selectedInstallation;
        private set => SetField(ref _selectedInstallation, value);
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
            var installations = _scanner.Scan();
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

public sealed class RelayCommand(Action execute, Func<bool>? canExecute = null) : ICommand
{
    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
    public void Execute(object? parameter) => execute();
    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}

