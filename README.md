# 截留 · Jieliu

常驻桌面的截图收纳托盘：自动接入新截图，拖出原图，选择、多选、预览；从托盘移出时保留文件。

| 平台 | 当前状态 |
| --- | --- |
| macOS 14+ | 已有 Swift / AppKit / SwiftUI 实现，可本地构建；正式签名公证尚未完成 |
| Windows 11 x64 | C# / WPF 原生首版，核心测试与交叉编译通过；Windows 真机验收待完成 |

默认取景框胶囊入口、B 帧缓冲展开样式，支持 A 标尺 / C 图层、中英文，以及仅系统托盘或菜单栏图标模式。

## 仓库结构

```text
apps/
  macos/                 Swift 源码、测试和应用资源
    Sources/
    Tests/
    Resources/
  windows/               C# 核心库、WPF 客户端与回归检查
design/                  原始 HTML 设计参考与使用说明
docs/                    平台说明、发布范围
scripts/                 macOS 与 Windows 检查、构建、打包脚本
Package.swift            macOS Swift Package 入口
```

构建缓存 `.build/` 和产物 `dist/` 不进入版本控制。当前仅整理本地仓库，没有执行 GitHub 上传或公开发布。

## macOS 本地开发

在 macOS 安装 Xcode Command Line Tools，在仓库根目录执行：

```sh
bash scripts/check.sh
bash scripts/build.sh
# 同时生成 Apple Silicon 与 Intel 二进制
UNIVERSAL=1 bash scripts/build.sh
bash scripts/package-local.sh
```

应用生成于 `dist/截留.app`。完整集成检查需要可用的图形桌面会话。

- [macOS 使用说明与验收边界](docs/macos.md)
- [Windows 客户端范围](apps/windows/README.md)
- [Windows 实现与验收](docs/windows.md)
- [视觉设计参考](design/README.md)
- [跨平台发布范围](docs/release-scope.md)
- [贡献说明](CONTRIBUTING.md)

## 许可证与分发

项目源码许可证尚未确定；当前没有授予 MIT 或其他开源许可证。正式公开前由维护者确认并加入根目录 `LICENSE`。

Geist 字体遵循独立的 [SIL OFL 1.1](apps/macos/Resources/Geist-OFL.txt)。本地构建的 macOS 包采用 ad-hoc 签名，不是已经公证的正式发行包。
