# AE 中英文切换器

一个用于识别 Adobe After Effects，并安全切换当前用户 AE 界面语言（简体中文或 English）的小工具。现提供 macOS 与 Windows 10/11 x64 版本。

## Windows 版

从 [GitHub Releases](https://github.com/dadaozei01/ae-language-switcher/releases) 下载 `AE-Language-Switcher-win-x64.exe`，双击即可运行，无需安装 .NET 或管理员权限。

- 支持 Windows 10/11 x64。
- 从卸载注册表与 `Program Files/Adobe` 自动查找所有 After Effects 正式版，排除 Render Engine，并允许选择要修改的具体版本。
- 切换前会检查 `AfterFX.exe` 是否正在运行，不会启动或结束任何 Adobe 进程。
- 每个版本独立读写 `%APPDATA%/Adobe/After Effects/<版本>/Debug Database.txt` 中的 `ApplicationLanguage`，可分别设置为 `zh_CN` 或 `en_US`。
- 修改前必须退出所有 AE。工具备份偏好文件、原子替换并读回验证；不会修改 Premiere Pro、Photoshop 或 `Program Files`。
- 旧的全局空白 `ae_force_english.txt` 会被安全隔离，避免它继续强制所有 AE 版本为英文；非空文件、目录或链接会被拒绝处理。
- `ApplicationLanguage` 是 AE 的内部版本级偏好，并非 Adobe 公开 API；AE 更新或重置偏好后可能需要重新设置。
- Windows 单文件 EXE 为自包含构建，不依赖预装 .NET Runtime。首次下载时，Microsoft Defender/SmartScreen 可能提示未知发布者；可核对 Release 同页的 SHA-256。当前版本未购买代码签名证书。

### Windows 构建

需要 .NET 8 SDK。在仓库根目录运行：

```powershell
dotnet test windows/AELanguageSwitcher.Windows.sln -c Release
dotnet publish windows/src/AELanguageSwitcher.App/AELanguageSwitcher.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:PublishTrimmed=false `
  -o windows/artifacts/win-x64
```

生成文件为 `windows/artifacts/win-x64/AE-Language-Switcher.exe`。

## 精简界面

Windows 主窗口列出所有检测到的 AE 版本。选择具体版本后可分别点击“切换为简体中文”或“切换为 English”；扫描和选择本身不会修改语言。

## macOS 系统与行为

- 需要 macOS 13 或更高版本。
- 自动扫描名称为 `Adobe After Effects*.app` 的主程序，排除 Render Engine，并读取版本、构建号、安装路径以及 `zh_CN`、`en_US` 资源状态用于资格判定；精简主界面不展示这些明细。
- 语言切换在 After Effects 下次启动时生效。
- 检测到 After Effects 正在运行时，相关切换操作仍可点击；点击后工具会重新检查进程，在修改语言偏好前阻止切换并显示“请先退出 AE”的提示。它不会启动、关闭或强制结束 AE 进程。
- “重新扫描”只读取应用包、系统首选语言、进程状态和 AE marker 状态，不会切换语言。

## 仅切换 After Effects

工具只修改 After Effects 自身识别的 `~/Documents/ae_force_english.txt`，不会写入 Premiere Pro 或 Photoshop 的应用偏好。marker 的存在会让当前用户安装的所有 AE 版本使用英文；工具选择扫描结果中版本最高的安装来检查中文资源资格。

## 安全 marker 规则

- 切换到英文时，只在 marker 不存在时原子创建一个空的普通文件；已经存在的普通文件保持不变。
- marker 若是符号链接、目录或其他非普通文件，工具会拒绝操作。
- 切换到中文时，仅接受经过文件身份复核的零字节普通 marker；有内容的文件不会被覆盖或删除。
- 合格的零字节 marker 会被原子改名为同目录下唯一的 `.ae-language-switcher-<UUID>.quarantine` 文件，从而停止影响 AE，同时保留恢复线索。工具不会递归删除 marker 路径。

## 切换到简体中文的前提

所选 AE 安装必须同时满足：

1. 应用包包含 `zh_CN` 简体中文资源；
2. macOS“语言与地区”的第一首选语言是简体中文。

缺少任一条件时，工具会阻止中文切换并说明原因。可参考 Adobe 官方文档：

- [安装并以简体中文或日文启动 After Effects](https://helpx.adobe.com/after-effects/desktop/get-started/language-support/install-launch-after-effects-simplified-chinese-japanese-languages.html)
- [After Effects UI language support](https://helpx.adobe.com/in/after-effects/using/improved-ui-language-support.html)

## macOS 构建、测试与打包

在项目根目录运行：

```bash
xcrun swift build
xcrun swift test
bash scripts/make_app_icon.sh
bash scripts/package_app.sh
```

图标源文件保存在 `Sources/AELanguageSwitcherApp/Resources/AppIconSource.png`，图标脚本仅对该正方形源图执行标准尺寸缩放，并生成 `AppIcon.icns`，不改动用户提供的画面构成。

打包脚本会先重新生成图标，再执行 release 构建、组装 app bundle、复制 `AppIcon.icns`、应用 ad-hoc 签名并严格验证签名。生成的应用位于：

```text
outputs/AE中英文切换器.app
```

可在 Finder 中双击，或仅在本机测试时运行：

```bash
open 'outputs/AE中英文切换器.app'
```

## 本地签名与 Gatekeeper

当前打包脚本使用 `codesign --sign -` 进行 ad-hoc 签名，适合本地构建和测试，但不是 Developer ID 签名，也没有经过 Apple 公证。通过互联网或其他带 quarantine 属性的渠道分发时，Gatekeeper 可能阻止直接打开；可在 Finder 中按住 Control 点击应用并选择“打开”，或在“系统设置 → 隐私与安全性”中确认打开。不要把本构建描述为已公证版本。

## 未来的 Developer ID 签名与公证

正式分发前，先在钥匙串中安装 Developer ID Application 证书，并通过环境变量提供真实凭据：

```bash
: "${DEVELOPER_ID_APPLICATION:?Set the Developer ID Application identity}"
: "${APPLE_ID:?Set the Apple ID used for notarization}"
: "${TEAM_ID:?Set the Apple Developer Team ID}"
: "${APP_SPECIFIC_PASSWORD:?Set an app-specific password}"

APP_PATH="$PWD/outputs/AE中英文切换器.app"
ARCHIVE_PATH="$PWD/outputs/AE中英文切换器-notarization.zip"

codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"
xcrun notarytool submit "$ARCHIVE_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"
```

只有 `notarytool` 返回成功、票据完成 staple 并通过最终验证后，才能称该产物已公证。
