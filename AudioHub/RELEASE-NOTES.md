# AudioHub for macOS 0.1.0 Preview

面向 macOS 12 及以上的开发预览版，同一个 PKG 同时包含 Intel x86_64 与 Apple Silicon arm64。

## 提供的功能

- 基于 Background Music 的应用音量控制、输出设备选择。
- Edge 标签页自动发现、独立静音/恢复、普通音视频元素音量调节。
- 静音保持播放；默认关闭上游自动暂停功能。
- 安装包自带 Edge 扩展与中文说明。

## 下载与首次使用

下载本页的 AudioHub-macOS12-Universal-0.1.0-preview.pkg；源代码 ZIP 不是安装包。
安装后启动“应用程序”中的 Background Music.app，点击菜单顶部“AudioHub 网页音源…”；通过“打开扩展文件夹”按钮导入 Edge。完整步骤见本页附带的中文说明。

## 预览版限制

尚未完成 Intel macOS 13.7.4、macOS 12 以及 Apple Silicon 的真实音频验收。云端构建与自动测试不能替代真机声音测试。
安装虚拟音频设备需要管理员授权。沿用上游应用名和驱动标识，会替换已安装的 Background Music，不能与原版同时使用。
安装包尚无 Developer ID 签名与 Apple 公证，系统可能提示无法验证开发者。请勿全局关闭系统安全保护。
当前仅配置 Edge；Chrome 等浏览器未完成适配。纯 Web Audio 的独立音量调节、受限网页及特殊音源不保证支持。

## 源码与许可

基于 https://github.com/kyleneideck/BackgroundMusic，保留上游历史、GPL-2.0-or-later 和 Apple 示例代码许可。
本仓库包含构建脚本、网页扩展和本机通信代码。Windows 版本使用不同基础项目，本仓库不包含 Windows/EarTrumpet 代码。
