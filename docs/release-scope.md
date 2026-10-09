# 截留：GitHub 与 Windows 发布范围草案

状态：用户已确认 Windows 保留 A/B/C、中英文、默认取景框胶囊及仅系统托盘图标模式，并已授权开始实现。Windows 原生首版已落地，真机验收待完成。当前仅本地开发，不创建 GitHub 仓库、不上传、不发布。

## 推荐方向

保留现有 Swift / AppKit / SwiftUI macOS 实现，新增 C# / WPF Windows 原生客户端。一个仓库维护两个客户端，共享视觉规范、交互约定和行为测试用例，不要求共享平台窗口代码。

建议 Windows 首版支持 Windows 11 x64，默认 B 展开样式、取景框胶囊入口，保留 A / C、仅系统托盘图标和中英文选项。Windows ARM64 支持待构建及实机验证后列入发行范围。

## 模块与依赖

| 模块 | 职责 | 依赖 |
| --- | --- | --- |
| shared-contract | 将现有 HTML 视觉、A/B/C、入口、8 槽历史、删除保留文件、中英文与快捷键差异写成两平台可验证约定 | 无 |
| windows-client | 截图目录监听、归档、持久化、原图拖放、选择/多选/预览、系统托盘、不抢焦点的窗口、多屏和缩放适配 | shared-contract |
| github-distribution | 仓库文档与许可证、平台构建检查、版本号与发布附件、macOS 签名公证及 Windows 包装流程 | shared-contract；双平台发行依赖 windows-client 验收 |

推进顺序：确认 shared-contract → Windows 客户端与 GitHub 发布准备 → 双平台验收 → 发布版本。macOS 源码可先公开，Windows 未验收前标为开发中，不宣称已有可用发行包。

## Windows 需要明确的行为

- 默认接入系统截图目录及用户明确指定的截图目录；通过系统已知文件夹定位，处理目录重定向，不硬编码用户名或英文路径。
- 系统截图工具自动保存的新图片可以接入；普通剪贴板图片不默认收集。仅写入剪贴板的截图是否接入，需另定识别和授权交互。
- macOS 的 `kMDItemIsScreenCapture` 不能作为 Windows 的实现契约。Windows 目录接入方案无法仅凭落盘图片可靠区分截图与用户复制进去的普通图片，界面必须说明接入目录的含义。
- 不覆盖同名文件，不因归档失败删除源文件；移出托盘及历史淘汰保留文件。直接保存在归档目录的文件也须处理新版本及重复事件。
- Ctrl 适配 macOS 的 Command 操作；拖放提供原文件复制，不以缩略图替代。
- 优先验证截图来源屏幕信息；仅凭文件无法可靠定位时，需要约定并显示回退策略。鼠标所在屏幕只能作为回退，不可宣称与截图来源总是一致。
- Windows 使用系统托盘，不模拟 macOS 菜单栏或摄像头；需要验证任务栏位置、混合 DPI、多显示器、全屏和睡眠恢复。

## 当前发布缺口

- Git 尚未配置远程仓库；账号、仓库名、可见性与许可证待用户指定。许可证建议 MIT；保留 Geist 字体的独立 OFL 声明。
- HTML 设计文件已收录于 `design/concepts.html`，正式公开前确认设计素材授权。
- 当前 macOS DMG 为 ad-hoc 本地测试包；正式发行的 Developer ID 签名与 Apple 公证尚未执行。
- Windows 源码、核心测试、构建脚本和自包含便携包流程已实现；签名、安装器及真机验收仍未完成。开发用 .NET SDK 位于本地忽略缓存，不随源码提交。
- 不将已有测试截图或用户真实截图作为公开仓库示例。发布示例使用合成素材。

## 待确认

1. Windows 实现阶段确认最低系统版本与测试设备；A/B/C 与中英文方向已确认。
2. 以后准备发布时再确认 GitHub 账号或目标仓库、公开/私有、许可证。
3. 是否具备 Windows 11 测试机器；没有时先准备 Windows CI 编译，但 GUI、拖放、多屏仍需实际验收。

## 官方参考

- [WPF 概览](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)：Windows 原生 .NET 桌面 UI，适合定制绘制、布局与交互。
- [Windows 截图工具](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots)：截图自动保存与截图工具操作。
- [Apple Developer ID](https://developer.apple.com/developer-id/)：macOS 对外分发的签名与公证。
