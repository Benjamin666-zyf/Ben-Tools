# Ben-Pake

Ben-Pake 是 Apple Silicon Mac 上使用的 SwiftUI 网站打包工具。它调用开源 [Pake CLI](https://github.com/tw93/Pake)，无需账号或激活。

1. 打开 Ben-Pake，填写网址和应用名称。可以选择本地图标并调整窗口尺寸。
2. 点击「生成 DMG」。默认保存到「下载」，完成后可以在 Finder 中定位。
3. 需要 Windows 安装包时，打开「Windows 打包」，选择 `windows-latest`，填写同一个网址和应用名称。完成后从该次运行下载包含 x64 MSI 的 Artifact。公开仓库请使用可公开的网址和配置。

使用本地打包需要 macOS 14 或更高版本、Node.js 22.12 或更高版本、Rust 和 Xcode 命令行工具。Ben-Pake 自带 Pake CLI 和 Node 依赖。首次打包需要联网下载编译所需的依赖。

开发时在仓库根目录运行 `./ben-pake/build.sh`。该命令使用 pnpm 锁文件和当前仓库的 Pake 源码，将 `Ben-Pake.app` 和 `Ben-Pake.dmg` 写入 `ben-pake/output`。构建使用本机临时签名。
