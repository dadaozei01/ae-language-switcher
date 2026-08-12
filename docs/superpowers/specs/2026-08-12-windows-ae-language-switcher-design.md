# Windows AE 中英文切换器设计

日期：2026-08-12

## 目标

在现有 macOS AE 中英文切换器项目中新增 Windows 10/11 x64 版本。Windows 用户下载一个自包含 `.exe` 后即可运行，不需要安装 .NET、PowerShell 模块或安装包。项目发布到新的公开 GitHub 仓库 `dadaozei01/ae-language-switcher`，并通过 GitHub Release 提供可下载程序和 SHA-256 校验文件。

## 范围

Windows 版只管理当前 Windows 用户的 After Effects 中文/English 切换。它不修改 Premiere Pro、Photoshop、Creative Cloud 或系统全局语言设置，不启动或结束 Adobe 进程，也不修改 AE 安装目录。

首个 Windows 版本支持 Windows 10/11 x64。ARM64、安装包、自动更新、Windows Store、代码签名、多语言 UI 和逐 AE 版本语言设置不在本期范围内。

## 技术方案

使用 C#、.NET 8 和 WPF 构建 Windows 原生桌面界面。采用 `win-x64`、self-contained、single-file 发布，使目标电脑无需预装 .NET。应用保持无第三方运行时依赖。

仓库保留现有 macOS Swift Package 的目录结构，并新增：

- `windows/src/AELanguageSwitcher.Core`：扫描、状态判断、进程检测和 marker 安全操作。
- `windows/src/AELanguageSwitcher.App`：WPF 界面和应用编排。
- `windows/tests/AELanguageSwitcher.Core.Tests`：Windows 核心逻辑自动测试。
- `.github/workflows/windows.yml`：Windows 测试、构建和 Release 发布。

核心逻辑与 WPF 分离。文件系统、进程、注册表、系统目录和语言信息通过窄接口注入，以便在测试中使用临时目录和确定性数据。

## AE 安装扫描

扫描器从以下来源收集候选安装：

1. 64 位和 32 位注册表视图中的卸载信息，筛选 Adobe After Effects；
2. `%ProgramFiles%\Adobe` 和 `%ProgramFiles(x86)%\Adobe` 下名为 `Adobe After Effects*` 的目录作为回退。

候选目录必须包含正式版主程序 `Support Files\AfterFX.exe`。扫描器排除 Render Engine、缺失主程序或无法读取版本信息的目录。版本优先读取 `AfterFX.exe` 的文件版本，无法读取时再解析目录名称。结果按数字版本降序排列，界面自动选择最高版本。

所有扫描操作只读。单个候选损坏或无权限时忽略该候选；只有扫描根本无法完成时才显示扫描错误。

## Windows 语言机制

Windows 版使用 AE 已识别的当前用户 marker：

`%USERPROFILE%\Documents\ae_force_english.txt`

实际 Documents 路径通过 `Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)` 获取，以支持 OneDrive、企业策略或用户自定义重定向，不拼接固定路径。

- marker 存在：当前有效语言显示为 English。
- marker 不存在且系统和所选 AE 满足中文资格：显示为简体中文。
- 其他情况：显示无法确定的系统默认状态，并说明原因。

marker 是当前用户级 AE 开关，因此同一用户安装的多个 AE 版本会一起切换；界面只使用最高版本安装判断资源资格。

## 中文资格

切换到简体中文必须同时满足：

1. 所选 AE 安装包含简体中文资源；扫描已知 AE 资源目录中可识别的 `zh_CN` 目录或资源文件。
2. Windows 当前用户首选 UI 语言为 `zh-CN` 或等价的简体中文语言标签。

如果资源布局无法识别，应用按“缺少中文资源”处理，不尝试猜测或修改安装目录。界面给出通过 Creative Cloud 安装中文资源、并在 Windows“语言和区域”中设置简体中文的指引。

## 安全切换

切换前重新检查 `AfterFX` 进程。若 AE 正在运行，显示提示并停止，不强制关闭进程。

切换到 English：

- marker 不存在时，以只创建、不覆盖语义创建零字节文件；
- marker 已是普通文件时保持原样，使操作幂等；
- marker 是目录、符号链接、junction、其他 Reparse Point 或非普通对象时拒绝操作。

切换到简体中文：

- 先验证中文资格；
- marker 不存在时视为已完成；
- 仅允许移除零字节、非 Reparse Point 的普通文件；
- 非空文件或任何不安全对象都拒绝操作，不覆盖、不递归删除。

文件操作错误保留原始系统错误信息，并转换为对用户可理解的中文状态和弹窗。应用不请求管理员权限。

## 界面

WPF 窗口沿用 macOS 版紧凑单按钮结构：

- 顶部显示“AE 语言切换”和只读的“中文 | English”状态；
- 中央主按钮根据当前状态显示“切换到 English”或“切换到中文”；
- 底部显示状态文本和“重新扫描”按钮；
- 忙碌、没有安装或状态不确定时禁用不安全操作；
- 应用启动、窗口重新获得焦点和用户点击重新扫描时刷新状态。

窗口采用系统字体、系统 DPI 缩放和键盘可访问控件，不实现自定义窗口框架或动画。

## 错误处理

应用区分以下用户可见状态：

- 未检测到 After Effects；
- After Effects 正在运行；
- 缺少简体中文资源；
- Windows 首选语言不是简体中文；
- marker 类型不安全；
- marker 非空；
- 扫描失败；
- 文件操作失败。

错误不会导致自动重试、进程终止、提权或对其他文件的补偿性修改。重新扫描是恢复界面状态的唯一显式操作。

## 测试

核心测试至少覆盖：

- 从注册表和 Program Files 回退目录发现 AE；
- 数字版本排序与最高版本选择；
- 排除 Render Engine、损坏安装和错误可执行文件；
- Documents 重定向路径的 marker 定位；
- marker 存在/不存在时的语言状态；
- 简体中文资源和 Windows UI 语言资格；
- AE 进程运行时阻止写入；
- 原子创建零字节 marker；
- 重复切换幂等；
- 删除零字节普通 marker；
- 拒绝非空文件、目录、符号链接、junction 和其他 Reparse Point；
- 文件竞争或路径在检查后被替换时安全失败。

GitHub Actions 使用 Windows runner 执行完整测试和 Release 发布。macOS 现有测试保留，不因 Windows 版本重构现有核心逻辑。

## GitHub 与发布

创建公开仓库 `dadaozei01/ae-language-switcher`。初次导入包含现有 macOS 项目、Windows 项目、统一 README 和构建工作流。本期不主动添加开源许可证；公开可见不等于授予再分发或修改权，后续由仓库所有者单独决定许可证。

Windows 工作流行为：

- 对推送和 Pull Request 运行 `dotnet test`；
- 对版本标签运行 Release 构建；
- 发布 `AE-Language-Switcher-Windows-x64.exe`；
- 生成并发布对应 `.sha256` 文件；
- 创建 GitHub Release，说明系统要求、使用步骤和变更摘要。

首个 Windows 版本不做 Authenticode 签名。README 和 Release 明确说明 Windows SmartScreen 可能显示“未知发布者”，并提供 SHA-256 校验方法。不得描述为已签名或已通过 Microsoft Store 审核。

## 验收标准

1. Windows 10/11 x64 用户下载一个 `.exe` 即可启动，不需要安装 .NET。
2. 应用能识别最高版本正式 AE，并排除 Render Engine。
3. AE 完全退出时可在中文和 English 之间切换；重新启动 AE 后生效。
4. AE 运行时、中文资格不满足或 marker 不安全时不修改文件。
5. 应用不读取或修改 PR、PS 的语言偏好与安装内容。
6. Windows 自动测试在 GitHub Actions 上通过。
7. GitHub Release 包含 Windows x64 `.exe` 和 SHA-256 文件。
