# Windows 按版本切换 AE 语言设计

## 目标

修复 Windows 版无法正确识别和切换 After Effects 语言的问题，并支持用户从所有已安装的正式版 After Effects 中选择一个版本，永久将该版本设置为简体中文或 English。设置完成后，从 Creative Cloud、开始菜单或安装目录正常启动该版本时都应沿用所选语言，不需要通过切换器启动。

## 已确认根因

现有程序只检查当前用户“文档”目录中的全局 `ae_force_english.txt`，再结合 .NET 进程的 `CurrentUICulture` 和 AE 语言资源推断状态。这个模型存在两个问题：

1. `ae_force_english.txt` 是当前用户下所有 AE 版本共用的英文覆盖，不能表达“AE 2024 是英文、AE 2025 是中文”。
2. 当前机器的 `CurrentUICulture` 为 `en-US`，而安装 UI culture 为 `zh-CN`。现有代码只读取前者，导致 marker 不存在时返回 `SystemDefault`，界面按钮被禁用。

本机各 AE 小版本的 `%APPDATA%\Adobe\After Effects\<版本>\Debug Database.txt` 中存在版本级 `ApplicationLanguage` 项。该项可以保存 `en_US` 或 `zh_CN`，并在 AE 重启后决定对应版本的界面语言。它是内部调试偏好，不是 Adobe 公开 API，因此实现必须采用严格的验证、备份和回滚策略。

## 产品行为

### 多版本选择

- 扫描卸载注册表和 `Program Files\Adobe` 下的所有正式版 After Effects，排除 Render Engine。
- 按语义版本从高到低显示全部安装，不再只暴露最高版本。
- 下拉项包含产品名和完整版本，例如 `Adobe After Effects 2025（25.3）`。
- 重新扫描时按可执行文件完整路径保留当前选择；原选择不存在时才选最高版本。
- 状态区显示所选版本、安装路径、当前语言以及 `zh_CN`、`en_US` 资源可用性。

### 语言检测

- 根据所选安装的完整产品版本映射到 `%APPDATA%\Adobe\After Effects\<major.minor>\Debug Database.txt`。
- 读取唯一的 `ApplicationLanguage` 行。文件采用制表符分隔，第二列为当前值，第三列保持 AE 的默认值。
- 第二列为 `en_US` 时显示 English；为 `zh_CN` 时显示简体中文。
- 第二列为空时，读取 Adobe CCX 中与相同产品版本匹配的最新 `productLanguage` 记录作为只读后备证据。
- 没有足够证据时显示“未设置”，不得根据 marker 或 .NET UI culture 猜测所选版本的语言。
- 全局 `ae_force_english.txt` 存在时，界面显示“全局 English 覆盖”，因为它优先影响所有版本。

### 版本级切换

- 界面提供 `切换为简体中文` 和 `切换为 English` 两个按钮。
- 当前语言对应按钮禁用；语言未知时两个按钮均可用。
- 中文切换要求所选安装存在 `zh_CN` 资源；English 切换要求存在 `en_US` 资源。
- 任意 `AfterFX.exe` 正在运行时阻止修改，且不自动结束进程。
- 切换只修改所选小版本偏好目录中的 `ApplicationLanguage` 第二列：简体中文写 `zh_CN`，English 写 `en_US`。不得修改其他键或其他版本目录。
- 写入后重新打开文件并读取该键；只有读回目标值才显示成功。
- 修改在所选 AE 下次普通启动时生效并保持，直至再次切换、AE 重置偏好或 Adobe 更新覆盖该内部偏好。

### 全局 marker 迁移

- 版本级设置不能与全局 `ae_force_english.txt` 共存，否则 marker 会强制所有版本为 English。
- marker 不存在时不做任何操作。
- marker 是零字节普通文件时，将其原子移动为同目录下带唯一标识的隔离备份，停止全局覆盖但保留恢复线索。
- marker 是非空文件、目录或重解析点时拒绝切换，不覆盖、不删除，也不递归处理。
- marker 迁移必须在版本偏好写入成功前保持可回滚；任一步失败时恢复原 marker 状态。

## 文件安全与回滚

- `Debug Database.txt` 不存在时不得盲目创建。提示用户先正常启动并退出该 AE 版本一次，再重新扫描。
- `ApplicationLanguage` 缺失、重复、列数异常或目标值非法时拒绝写入。
- 保留原始字节编码、BOM 和换行风格。
- 修改前在同目录创建带 UTC 时间戳和唯一标识的备份。
- 将完整新内容写入同目录临时文件，刷新到磁盘后使用原子替换；不得直接截断原文件。
- 写入、验证或 marker 迁移失败时自动恢复原偏好文件和原 marker 状态。
- 备份不得包含 AE 项目内容或任何账号凭据；工具不得读取、保存或打印 Token。

## 界面与状态管理

- 窗口扩大到能容纳版本选择、路径、资源状态和两个语言按钮，保持紧凑的单窗口 WPF 设计。
- 扫描、选择和切换期间只能有一个操作进行；切换期间禁用版本选择、重新扫描及两个语言按钮。
- 选择不同版本时只重新检测该版本状态，不写入文件。
- 成功信息明确包含版本和目标语言，例如“After Effects 25.3 已设置为 English，重启该版本后生效”。
- 错误信息区分：AE 正在运行、偏好数据库未生成、语言键异常、语言资源缺失、全局 marker 不安全、权限不足、文件占用、写入失败、验证失败和回滚失败。

## 图标

- Windows 版复用 macOS 图标源 `Sources/AELanguageSwitcherApp/Resources/AppIconSource.png`，不重新设计图形。
- 从同一源生成包含 Windows 常用尺寸的 `AppIcon.ico`。
- 在 WPF 项目中同时设置 `ApplicationIcon` 和窗口 `Icon`，确保 EXE、资源管理器、任务栏和标题栏使用一致图标。
- 图标转换脚本或构建步骤必须可重复执行，生成结果纳入仓库。

## 组件边界

- `InstallationScanner`：返回全部安装及完整产品版本，不负责选择。
- `PreferenceLocator`：把安装版本映射到准确的小版本偏好目录和 Debug Database 路径。
- `VersionLanguageDetector`：只读解析 `ApplicationLanguage`，必要时读取匹配版本的 CCX 后备记录。
- `VersionLanguageSwitcher`：验证、备份、原子写入、读回验证和回滚单个版本偏好。
- `GlobalMarkerMigrator`：检查并安全隔离旧全局 marker，可在失败时恢复。
- `MainViewModel`：维护安装列表、用户选择、命令状态、运行进程检查和用户可见结果。

## 测试策略

- 扫描测试：多版本去重、排序、排除 Render Engine、完整版本保留。
- 选择测试：首次默认最高版本，重新扫描保留相同可执行路径，版本消失时合理回退。
- 定位测试：`24.6.x` 映射 `24.6`，`25.3.x` 映射 `25.3`，畸形版本拒绝。
- 检测测试：`en_US`、`zh_CN`、空值、未知值、缺失键、重复键和 CCX 精确版本后备。
- 写入测试：只改变第二列、保留第三列和其他全部字节语义、保留编码与换行、原子替换、读回验证。
- 回滚测试：临时写入失败、替换失败、验证失败和 marker 迁移失败时恢复原状。
- marker 测试：不存在、空普通文件、非空文件、目录和重解析点。
- ViewModel 测试：所有版本可选、选择变更刷新、AE 运行时零修改、按钮启用状态及明确错误。
- 构建验证：运行全部 Windows 测试、Release 构建、win-x64 自包含单文件发布，验证 EXE 图标资源和 SHA-256。

## 交付与验收

- 不覆盖桌面上的旧 `AE-Language-Switcher-win-x64.exe`。
- 新 EXE 和 `.sha256` 先输出到 Codex 交付目录供用户测试。
- 验收场景：将 AE 2024 设置为 English、AE 2025 设置为简体中文，分别普通启动后各自保持目标语言；重新打开切换器能读回两个版本的独立状态。
- 若某个 AE 版本未生成 Debug Database、缺少目标语言资源或 Adobe 已移除 `ApplicationLanguage`，工具必须明确说明该版本无法安全自动切换，不得报告虚假成功。
