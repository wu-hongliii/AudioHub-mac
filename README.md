# AudioHub for macOS

基于 [Background Music](https://github.com/kyleneideck/BackgroundMusic) 的音源中控台修改版：应用音量控制 + Edge 网页标签页独立静音和调音量。

**状态：开发预览版，目标 macOS 12+，同时构建 Intel x86_64 和 Apple Silicon arm64。通过编译不等于完成真实音频验收。**

- 应用音源：沿用 Background Music 虚拟音频设备与菜单栏混音器。
- 网页音源：菜单顶部“AudioHub 网页音源…”打开控制窗口；首次需要导入随包 Edge 扩展。
- 静音不会暂停音视频，默认禁用上游自动暂停功能。
- 目前仅适配 Edge；Chrome、Firefox、Safari 尚未验证。

## 下载与安装

参阅 Releases 中的预览安装包及 [中文使用说明](AudioHub/使用说明.md)。没有发布附件时，代表当前还在构建或验证，不能将源代码 ZIP 当成应用安装包。

本版保留上游内部应用名、驱动 ID 和安装位置。安装后应用名称仍为 Background Music.app；会替换现有 Background Music，不能与原版并行。尚无 Developer ID 签名和 Apple 公证。

## 构建

在装有 Xcode 的 Mac 上执行 `bash package.sh`。最低部署版本设为 12.0，应用、驱动、本机桥和安装辅助工具需同时包含 x86_64 / arm64。GitHub Actions 负责构建检查；实际音频需分别在 Intel 和 M 系列机器上验收。

浏览器协议测试：`node --test AudioHub/tests/edge-protocol.test.mjs`。

## 真机状态

| 环境 | 状态 |
|---|---|
| Intel / macOS 13.7.4 | 待真机验证 |
| macOS 12 | 待真机验证 |
| Apple Silicon | 待真机验证 |

## 来源与许可

Mac 基础来自 Background Music；保留 GPL-2.0-or-later 和 Apple 示例代码许可。本仓库独立于 Windows/EarTrumpet 版本，不混用其许可证。上游原始说明见 [README.upstream.md](README.upstream.md)。

AudioHub 新增文件位于 AudioHub/；BGMAppDelegate.mm 接入网页窗口并关闭自动暂停，package.sh 增加本机桥与扩展打包。扩展与 Windows 版使用相同协议，此处的新增代码按 GPL-2.0-or-later 提供。
