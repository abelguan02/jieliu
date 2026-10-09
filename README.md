# 截留 · Jieliu

Swift / AppKit / SwiftUI 原生 macOS 截图收纳工具，最低 macOS 14。

## 运行

打开 `dist/截留.app`，在首次使用引导中点击「开始收纳」。首次访问桌面时允许系统弹出的文件夹权限请求。状态栏图标提供设置、展开托盘和退出。

建议按 ⌘⇧5，在「选项」里关闭「显示浮动缩略图」。软件不会擅自修改系统截图设置，也不会接管系统截图快捷键。

新截图默认移动到 `~/Pictures/Screenshots`。启动之前已经存在的图片不会被批量移动。保存目录可更改；更改仅影响之后生成的截图。

## 操作

- 鼠标进入顶部胶囊展开托盘；新截图自动展开。
- 默认 B 帧缓冲，可从菜单或设置切换 A 标尺 / C 图层；托盘拥有键盘焦点时可按 A / B / C。
- 单击选择，⇧ / ⌘ 多选，⌘A 全选，左右方向键切换，⇧ 加方向键追加选择。
- 拖到支持文件或图像拖放的 App；仅提供复制操作。图像数据按需读取原文件，不使用缩略图代替原图。
- 空格或双击预览，预览内左右键切换，空格 / Esc / 点击关闭。
- Delete 只从托盘移出，保留归档文件。8 个槽位满后覆盖最旧槽位的记录，保留文件。B 按槽位地址显示，A / C 按新旧显示。
- ⌘C 将选中的文件复制到剪贴板。退出重开后恢复托盘记录和 B 的写指针。

## 构建与检查

```sh
bash scripts/check.sh
bash scripts/build.sh
UNIVERSAL=1 bash scripts/build.sh
bash scripts/package-local.sh
```

无需第三方 Swift 包。检查使用可执行的 Swift 断言程序，Command Line Tools 环境也能运行，不要求 XCTest。构建缓存位于 `.build`。部分受限宿主需要允许 `dsymutil` 生成发布调试符号。

检查覆盖：循环缓冲、移出保留文件、历史恢复、同名文件归档、重复检测、位置解析、目录事件、延迟到达的截图标记、排除旧文件和普通图片、保留拖拽原始字节，以及三种视图的原生选择 / 预览 / 移出事件。实际 NSPanel 在本机连接的 1 块显示器上验证了自动出现不抢键盘焦点。面板检查需要访问 WindowServer；受限沙箱中无可见显示器时会明确失败，需在普通本地终端运行。`dist/Previews` 包含原生离屏渲染结果。

## 实现

- `TrayCore`：带校验的持久化历史、截图元数据和不覆盖目标的归档。
- `ScreenshotWatcher`：目录事件负责低延迟，Spotlight 查询补充其他用户目录；等待文件尺寸稳定后读取截图标记，归档成功后才通知界面。
- `TrayView`：原生绘制 HTML 的槽位、标尺、图层、RGB 写入指针、蚂蚁线和尺寸标签；系统文件拖拽和无障碍节点。
- `CaptureEffect`：独立、不接收鼠标事件的动画窗口。只绘制截图文件的像素，不请求屏幕录制权限。
- `TrayController`：每个显示器独立的非激活面板、悬停 / 自动收起和动画队列。
- `SettingsView`：SwiftUI 引导、目录、视觉方案、音效、自动收起及登录启动。

参考：`/Users/abelguan/Desktop/ScreenShotClaude/design/concepts.html`，SHA-256 `a0179ca4574221acaee2f86ea3887bed6c9eebbb5ac72230cd6b5251c91466c0`。网页中的模拟桌面、模拟截屏工具和说明面板不属于常驻托盘窗口。系统快捷键仍由 macOS 处理。

字体来自 [Vercel Geist](https://github.com/vercel/geist-font)，SIL OFL 1.1，许可证随 App 打包。仓库以 Base64 保存原始字体，构建时解码到资源目录，运行时仅在当前进程注册。

## 当前验收边界

这是可运行的原生实现；尚未完成与 HTML 的逐帧、逐像素一致性验收，不能标记为「完美复刻」。原生动画采用相同阶段和主要视觉元素，曲线、粒子路径、退出动效及声音仍与浏览器实现有差异。

截图的位置元数据不是公开稳定契约，真实系统在不同版本 / 截图方式下是否始终写入，需要真机覆盖验证。可读到 `kMDItemScreenCaptureGlobalRect` 时按与屏幕相交面积定位；缺失时先匹配全屏像素尺寸，仍不唯一则使用鼠标所在屏幕，并显示位置不可用提示。文件不会因为缺失位置而丢失。

已验证的是带真实二进制扩展属性的临时文件链路，尚未实测用户系统的全部截图快捷键、多显示器 / Spaces / 全屏组合、微信 / Figma / 邮件 / Finder 各版本的实际拖入效果，以及 macOS 14 和 Intel 真机运行。通用二进制包含 arm64 和 x86_64，交叉编译成功不等同于两类硬件都已实测。

只写到剪贴板、尚未落盘的系统截图不在自动捕获范围内。Spotlight 索引禁用的自定义目录需要重新启动监听，使其进入目录监听范围。失败信息可在设置中查看，归档失败时不删除源文件。

## 对外分发

`scripts/build.sh` 未指定签名身份时生成 ad-hoc 签名的本地测试 App。`Jieliu-1.0.0-local.dmg` 仅用于本地测试，不是已公证的正式发行包。

正式分发需要用户的 Developer ID Application 证书及已配置的 notarization Keychain profile：

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' bash scripts/release.sh
```

该脚本构建通用 App、签名、提交 Apple 公证、staple、公证 DMG 并执行 Gatekeeper 检查。它会将产物上传到 Apple，仅在用户授权正式分发时运行。当前未调用公证或上传。

官方接口参考：[NSMetadataQuery 更新](https://developer.apple.com/documentation/foundation/nsmetadataqueryupdateaddeditemskey)、[原生拖拽](https://developer.apple.com/documentation/appkit/nsdraggingitem)、[非激活面板](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)、[Developer ID](https://developer.apple.com/developer-id/)。
