# Windows 双版本发布设计

## 目标

在功能、图标和版本号完全一致的前提下，同时发布免运行库版和小体积版。默认推荐免运行库版，让普通用户仍可直接双击使用；已经安装 .NET 8 Desktop Runtime 的用户可以选择小体积版。

## 发布物

### 免运行库版

- 文件名：`AE-Language-Switcher-win-x64.exe`
- 使用 `win-x64`、self-contained、single-file 发布。
- 开启 .NET 单文件压缩，降低下载体积。
- 不启用 trimming；WPF 对裁剪的兼容风险不值得为本工具承担。
- 用户无需预装 .NET，README 和 Release 将其标为推荐下载。

### 小体积版

- 文件名：`AE-Language-Switcher-win-x64-lite.exe`
- 使用 `win-x64`、framework-dependent、single-file 发布。
- 依赖 Microsoft .NET 8 Desktop Runtime x64。
- 缺少运行库时由 .NET 主机显示缺失框架及下载提示，不在应用内重复实现启动前检查。

### 校验文件

每个 EXE 生成独立的 ASCII SHA-256 文件：

- `AE-Language-Switcher-win-x64.exe.sha256`
- `AE-Language-Switcher-win-x64-lite.exe.sha256`

校验文件内容使用小写哈希、两个空格和对应文件名，结尾保留换行。

## 构建与自动发布

GitHub Actions 在同一 Windows 作业中先运行现有完整测试，然后分别发布两个变体。构建产物同时进入 Actions artifact；`v*` 标签发布时，四个文件全部附加到 GitHub Release。两个构建使用相同源代码和应用图标，不复制第二套项目。

项目默认属性继续表达免运行库版。小体积版通过明确的发布参数覆盖 `SelfContained=false`，避免改变本地常规构建的行为。免运行库版通过 `EnableCompressionInSingleFile=true` 开启压缩。

## 文档与用户选择

README 的 Windows 下载说明首先推荐免运行库版，并用简短对照说明：

- 不确定选哪个：下载免运行库版。
- 已安装 .NET 8 Desktop Runtime x64 且希望下载更小：选择 lite 版。
- 两版功能、图标和语言切换能力相同。

文档不得承诺固定的文件大小，因为 .NET SDK 和运行时补丁会改变产物体积；应记录实际构建结果。

## 验证标准

- 现有 Windows 测试全部通过。
- 两个 EXE 均为单文件，并能在已安装 .NET 8 Desktop Runtime 的构建机上打开主窗口。
- 免运行库版在临时移除框架依赖不可行的情况下，通过发布元数据确认是 self-contained。
- lite 版通过发布元数据确认是 framework-dependent。
- 免运行库版必须显著小于当前约 162 MB 的未压缩文件；若压缩收益异常，停止交付并调查。
- 两个 SHA-256 文件都与对应 EXE 重新计算的结果一致。
- Release 工作流和 README 使用完全相同的四个文件名。

## 不在本次范围

- 不使用 WPF trimming 或 NativeAOT。
- 不改变语言检测、语言写入、备份或回滚逻辑。
- 不引入安装程序、自动更新器或代码签名服务。
- 不覆盖用户桌面上的旧 EXE；新本地产物仍交付到当前任务的 `outputs` 目录。
