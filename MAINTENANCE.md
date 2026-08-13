# AE 中英文切换器维护记录

## 当前版本

- 平台：macOS（Apple Silicon / arm64）
- 安装位置：`/Applications/AE中英文切换器.app`
- 功能：自动识别最高版本 After Effects，并在中文与 English 之间一键切换
- macOS 语言标记：`~/Documents/ae_force_english.txt`。AE 26 的自身框架明确读取该
  标记；macOS 的应用级 `AppleLanguages` 对 AE 26 的界面语言无效。
- 兼容清理：切换时会移除旧故障版本写入 AE Bundle ID
  `com.adobe.AfterEffects.application` 的无效 `AppleLanguages` 覆盖。

### Windows

- 平台：Windows 10/11 x64，.NET 8 WPF 自包含单文件。
- 发布文件：`AE-Language-Switcher-win-x64.exe`。
- 安装检测：64/32 位卸载注册表，并回退扫描 `Program Files/Adobe`；排除 Render Engine，返回全部版本供用户选择。
- Windows 版本级语言：`%APPDATA%/Adobe/After Effects/<major.minor>/Debug Database.txt` 的 `ApplicationLanguage` 当前值。
- 进程检测：任何名为 `AfterFX` 的进程运行时阻止切换。
- 简体中文资格：所选 AE 存在 `zh_CN` 资源；English 要求 `en_US` 资源。
- 写入前备份并迁移旧全局空 marker，使用同目录临时文件和原子替换，读回验证失败时回滚。
- 构建发布：`.github/workflows/windows.yml` 在 Windows runner 上测试并生成自包含 `win-x64` 单文件；`v*` 标签会创建 GitHub Release，并附带 EXE 与 SHA-256。

## PR 曾被联动的原因

- 源码没有扫描、写入或删除 Premiere Pro 的文件和偏好；本机 PR 26 主程序中也未
  检出 `ae_force_english.txt`，而 AE 26 的 `AfterFXLib` 明确包含该标记名。
- 用户观察到 PR 只联动一次、后续不再受影响，因此不能把该现象归因于 AE 标记。
  切换器继续只修改 AE 实际识别的标记，不触碰 PR 或 PS 的偏好。

## Windows 安全规则

- 切换英文时，仅在标记不存在时原子创建空文件。
- 切换中文时，仅将零字节普通文件原子改名为隐藏隔离文件；目录、重解析点和非空文件均拒绝操作。
- Windows 版不写注册表、不改 Adobe 安装目录、不需要管理员权限，也不修改 PR/PS 偏好。

## 默认工作方式

- 后续小改动默认采用轻量流程：一次实现、一次必要的针对性验证、一次交付。
- 不默认启用多代理、多轮代码审查、重复全量测试或重新打包。
- 只有涉及语言标记写入、安全逻辑、跨平台重构或正式公开发布时，才升级为严格验证流程。
