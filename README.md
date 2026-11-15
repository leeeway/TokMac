# TokMac 🎵

<p align="center">
  <img src="Resources/AppIcon_1024.png" width="128" height="128" alt="TokMac Logo" />
</p>

<p align="center">
  <b>A lightweight, distraction-free macOS desktop app for TikTok.</b><br>
  极简、沉浸、超轻量的 macOS 原生 TikTok 桌面客户端。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%2F%20Intel-blue" alt="Architecture" />
  <img src="https://img.shields.io/badge/Language-Swift%206-orange?logo=swift" alt="Language" />
  <img src="https://img.shields.io/badge/Binary%20Size-~200%20KB-success" alt="Size" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

## ✨ 核心亮点 / Features

- 📱 **专为刷视频设计的比例**：默认采用 420×780 仿手机黄金比例窗口，边角挂屏摸鱼极其舒适。
- 📌 **窗口置顶 (Always on Top)**：支持一键将窗口置顶于所有应用最前端，快捷键 `Cmd + T`。
- ⚡️ **丝滑键盘快捷键**：
  - `↓` 或 `J` / `S`：切换下一个视频
  - `↑` 或 `K` / `W`：切换上一个视频
  - `Space`：播放 / 暂停
  - `M`：静音 / 取消静音
  - `L`：点赞视频
- 🔐 **支持完整账号登录 & 长期免登**：
  - 基于 macOS 原生 `WKWebsiteDataStore`，持久化保留 Cookies & Session，免去重复登录困扰；
  - 完美支持 Google、Apple ID、Twitter、手机号等第三方 OAuth 弹窗登录。
- 🧼 **纯净去干扰模式**：自动屏蔽网页端冗余的“下载桌面版 APP”、各种营销弹窗与宽屏大边栏，回归纯净内容流。
- 🪶 **极度轻量与节能**：基于原生 WebKit 框架打造，运行内存仅约 **30~60 MB**（相比 Electron 节省 90% 内存），二进制体积不足 **1 MB**。
- 🔄 **自动连播功能**：视频播完后可自动滑至下一个视频，解放双手。

---

## ⌨️ 常用快捷键 / Keyboard Shortcuts

| 快捷键 | 功能描述 / Description |
| :--- | :--- |
| `↓` / `J` | 切换下一个视频 (Next Video) |
| `↑` / `K` | 切换上一个视频 (Previous Video) |
| `Space` | 播放 / 暂停 (Play / Pause) |
| `M` | 静音 / 恢复声音 (Mute / Unmute) |
| `L` | 点赞当前视频 (Like Video) |
| `Cmd + T` | 切换窗口置顶 (Toggle Always on Top) |
| `Cmd + 1` | 切换手机竖屏模式 (Phone Mode 420×780) |
| `Cmd + 2` | 切换宽屏桌面模式 (Desktop Mode 1080×750) |
| `Cmd + 3` | 切换极简迷你模式 (Mini Mode 340×600) |
| `Cmd + Shift + C` | 切换纯净模式 (Toggle Clean Mode) |
| `Cmd + Shift + A` | 切换自动连播下一个 (Toggle Auto Next) |
| `Cmd + R` | 刷新页面 (Reload) |
| `Cmd + [` | 返回上一页 (Go Back) |
| `Cmd + ]` | 前进到下一页 (Go Forward) |

---

## 🛠️ 构建与运行 / Build from Source

### 环境要求
- macOS 13.0+ (Ventura, Sonoma, Sequoia)
- Xcode Command Line Tools 或 Swift 5.9+

### 一键构建与启动
```bash
# 1. 克隆代码库
git clone https://github.com/leeeway/TokMac.git
cd TokMac

# 2. 编译打包出原生 TokMac.app
./build_app.sh

# 3. 运行应用
open build/TokMac.app
```

您也可以直接使用 Swift 运行：
```bash
swift run TokMac
```

---

## 📂 项目结构 / Project Structure

```text
TokMac/
├── Package.swift               # Swift Package Manager 构建文件
├── build_app.sh                # 一键编译并打包生成 TokMac.app
├── Resources/
│   ├── AppIcon.icns            # macOS 高清应用图标
│   ├── AppIcon_1024.png        # 1024x1024 设计源图
│   ├── Info.plist              # 应用 Bundle 元数据
│   └── generate_icon.py        # 图标生成脚本
└── Sources/TokMac/
    ├── main.swift              # 程序入口
    ├── AppDelegate.swift       # 应用生命周期与全局快捷菜单
    ├── MainWindowController.swift # 沉浸式窗口与状态控制
    ├── WebViewController.swift # WebKit 控制器、会话持久化与登录弹窗兼容
    └── InjectedScripts.swift   # 去广告纯净样式与按键映射脚本
```

---

## 📄 开源许可 / License

本项目基于 [MIT License](LICENSE) 开源。
欢迎提出 Issue 和 Pull Request！
