# TokMac 🎵

<p align="center">
  <img src="Resources/AppIcon_1024.png" width="128" height="128" alt="TokMac Logo" />
</p>

<p align="center">
  <b>A lightweight, distraction-free desktop app for TikTok (macOS & Windows).</b><br>
  极简、沉浸、超轻量的 TikTok 桌面客户端（支持 macOS 与 Windows）。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-black?logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?logo=windows" alt="Windows" />
  <img src="https://img.shields.io/badge/Architecture-Universal-blue" alt="Architecture" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

## 📥 下载安装 / Downloads

前往 [**GitHub Releases**](https://github.com/leeeway/TokMac/releases/latest) 下载对应平台最新版本：

| 平台 (Platform) | 下载文件 (File) | 说明 (Description) |
| :--- | :--- | :--- |
| **macOS** | [`TokMac-1.0.0.dmg`](https://github.com/leeeway/TokMac/releases/latest) | 双击打开 DMG，拖入 Applications 即可使用 |
| **Windows** (安装向导) | [`TokMac-Setup-1.0.0.exe`](https://github.com/leeeway/TokMac/releases/latest) | Windows 快速安装向导，自动创建桌面与开始菜单图标 |
| **Windows** (免安装便携版) | [`TokMac-Windows-Portable.zip`](https://github.com/leeeway/TokMac/releases/latest) | 解压后双击 `TokMac.exe`，需安装 WebView2 Runtime |

---

## ✨ 核心亮点 / Features

- 🖥️ **跨平台原生引擎**：
  - **macOS**：基于 Swift + WebKit 原生架构，提供 Apple Silicon / Intel Universal 应用。
  - **Windows**：基于 .NET 10 + Microsoft Edge WebView2 打造，支持 Windows 11 暗黑主题与任务栏进度。
- 📱/💻 **双模式一键切换**：
  - **宽屏舒适模式 (1080×760)**：完整展现频道侧边栏与视频，右侧评论区宽敞展开，阅读互动毫无遮挡。
  - **竖屏挂屏模式 (520×840)**：仿手机黄金比例，边写代码边摸鱼刷视频。
- ⬇️ **视频智能下载 & 实时进度**：
  - 支持快捷键 `Cmd+S` / `Ctrl+S`、工具栏按钮及鼠标右键下载。
  - 自由弹窗选择保存文件夹与文件名。
  - 原生悬浮进度条（HUD），实时显示下载进度与大小，下载完成可一键在访达/资源管理器中直达定位。
  - 同时进行一个下载；先保存到目标目录的临时文件，成功后再原子替换，失败或取消不会截断已有视频。
  - Blob 视频交给浏览器原生流式下载，不再通过网页消息传输整段 Base64；MediaSource 等不可下载的视频流会显示错误。
- 📌 **窗口一键置顶 (Always on Top)**：点击工具栏或按快捷键置顶，保持窗口永远浮在其他软件之上。
- 🔐 **支持完整账号登录 & 长期免登**：持久化保留 Cookies & Session，完美支持 Google、Apple ID、手机验证码等登录。
- 🧼 **纯净去干扰**：自动过滤各类下载手机 App 的干扰横幅，还原纯净浏览体验。

---

## ⌨️ 常用快捷键 / Keyboard Shortcuts

| 功能 (Feature) | macOS 快捷键 | Windows 快捷键 |
| :--- | :--- | :--- |
| **下载当前视频** | `Cmd + S` | `Ctrl + S` |
| **切换窗口置顶** | `Cmd + T` | `Ctrl + T` |
| **切换竖屏小窗** | `Cmd + 1` | `Ctrl + 1` |
| **切换宽屏桌面** | `Cmd + 2` | `Ctrl + 2` |
| **刷新页面** | `Cmd + R` | `F5` / `Ctrl + R` |
| **全屏切换** | `Cmd + Ctrl + F` | `F11`（`Esc` 退出） |

---

## 🛠️ 本地编译构建 / Build from Source

### macOS (Swift)

需要 macOS 13+ 和支持 Swift 5.9+ 的 Xcode Command Line Tools。构建脚本会分别编译 arm64、x86_64，再合并为 Universal 应用。

```bash
git clone https://github.com/leeeway/TokMac.git
cd TokMac
./create_dmg.sh
```

输出位于 `build/`。构建和打包不会安装、删除或替换 `/Applications` 中的应用；需要安装时，将生成的 `TokMac.app` 拖入 Applications。默认是仅供本地测试的 ad-hoc 开发构建，未经 Apple 公证，不能作为通过 Gatekeeper 的正式安装包发布。

### macOS 正式签名与公证

本地正式打包需要钥匙串中已安装的 **Developer ID Application** 证书及私钥，以及 `notarytool` 公证凭据。先通过 `xcrun notarytool store-credentials` 配置钥匙串 profile，再运行：

```bash
export TOKMAC_SIGNING_MODE=distribution
export CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_KEYCHAIN_PROFILE='TokMac-notary'
./create_dmg.sh
```

也可以设置 `NOTARY_KEY_PATH`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID`，使用 App Store Connect API key 替代钥匙串 profile。

正式模式会启用 hardened runtime 和可信时间戳，提交 App 与 DMG 到 Apple 公证，分别装订并验证公证票据，再执行 Gatekeeper 评估。证书、公证状态或评估不通过时立即停止。`build/macos-release-status.json` 记录已验证产物的版本、签名模式和 SHA-256。

GitHub Actions 使用以下仓库 Secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | 包含证书及私钥的 `.p12` 文件，以 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `MACOS_SIGNING_IDENTITY` | 完整的 Developer ID Application 签名名称或其 SHA-1 |
| `APPLE_NOTARY_KEY_P8` | App Store Connect API 私钥的完整 `.p8` 内容 |
| `APPLE_NOTARY_KEY_ID` | API key ID |
| `APPLE_NOTARY_ISSUER_ID` | API issuer ID |

标签构建强制使用正式模式；没有配置这些凭据时不会退回 ad-hoc 发布。普通分支默认生成开发产物；设置仓库变量 `MACOS_SIGNING_ENABLED=true` 可让分支构建也执行完整公证。PR 不导入签名凭据。CI 仅在临时钥匙串中导入证书，结束时删除钥匙串和 API key 文件。自动发布和手动重发都会校验公证状态及 DMG 校验和。

Apple 流程参考：[Developer ID](https://developer.apple.com/developer-id/)、[公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

### Windows (.NET 10 + WebView2)

需要 .NET 10 SDK；运行应用需要 Windows 10 1809+ / Windows 11 和 Microsoft Edge WebView2 Runtime（.NET 自包含发布不包含此浏览器运行时）。

```powershell
git clone https://github.com/leeeway/TokMac.git
cd TokMac\windows
dotnet publish TokMac.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ..\build_win
```

### 验证与版本发布

```bash
# 两个平台共用的浏览器脚本回归测试（需要 Node.js 18+）
node --test tests/scripts.test.cjs

# macOS 响应校验、原文件保护和本地 Blob 下载集成测试
./tests/run-swift-tests.sh --webkit

# 跨平台文件保存、重定向和 Cookie 隔离检查（需要 .NET 10 SDK）
dotnet run --project tests/windows/DownloadFileTests.csproj -c Release

# Windows 本机窗口全屏/恢复测试（不导航到 TikTok）
dotnet run --project tests/windows-ui/WindowTests.csproj -c Release

# 签名、公证失败处理和发布入口校验（使用隔离测试工具，不需要真实证书）
python3 tests/signing_flow_test.py
python3 tests/release_validation_test.py
```

默认版本读取仓库根目录的 `VERSION`。CI 的普通推送和 PR 仅测试、构建并保存产物；推送 `vX.Y.Z` 标签时，所有产物使用标签版本，并创建对应 Release。已有 Release 的附件不会被自动覆盖；只有完成签名、公证和 Gatekeeper 验证的 macOS 产物允许发布。如需同版本重新发布，可手动运行 `Republish Existing Release` 工作流，指定已通过的构建编号；工作流会核对构建提交与现有标签一致，再替换附件。

---

## 📄 开源许可 / License

本项目基于 [MIT 许可证](LICENSE) 开源发布。
