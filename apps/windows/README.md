# Windows 客户端

状态：Windows 原生首版已实现，可交叉编译；核心文件与历史检查已在 macOS 执行，Windows 图形桌面尚待真机验收。

已确认的产品方向：

- 默认屏幕顶部取景框胶囊，可选择仅系统托盘图标。
- 收起入口和 A / B / C 展开样式独立选择，默认 B。
- 中文和 English；原文件拖放、多选、预览，移出托盘保留文件。
- 保持 8 槽历史和同名文件不覆盖的约定。

使用 C# / WPF、.NET 10，面向 Windows 11 x64。`Jieliu.Core` 为文件与历史逻辑，`Jieliu.Windows` 为客户端，`Jieliu.Checks` 为核心回归测试。构建产物 `bin/`、`obj/` 不提交。

## 开始使用

解压便携包后运行 `Jieliu.exe`，保留同目录的运行时及资源文件。程序在系统托盘显示取景框图标；右键进入设置，左键展开。

在系统截图工具中启用自动保存，并将其目录与截留设置中的「截图接入文件夹」保持一致。默认使用 Windows 已知截图文件夹。该目录内新增或修改的普通图片也会被接入；只在剪贴板中的截图不会接入。

拖出复制原文件；Ctrl/Shift 多选、Ctrl+A 全选、Ctrl+C 复制、Space / 双击预览、Delete 移出但保留文件。历史限制为最近 8 张。新截图在鼠标所在屏幕展开，尚不能可靠定位原截图屏幕。

## 构建

开发需要 .NET 10 SDK，在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows-check.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows-build.ps1
```

输出 `dist/Jieliu-win-x64-0.1.2.zip`，自包含 .NET 运行时；按版本独立输出，保留旧包。Windows 真机图形检查加 `-Gui` 参数运行 `windows-check.ps1`，运行前确认电脑空闲。

0.1.1 已加入胶囊展开/收起、截图入槽、记录位移、移出归档、预览及动态选中框。动效默认开启，遵循 Windows 系统动画设置；应用设置会提示系统是否关闭了动画。

0.1.2 按原稿加入 C 的旋转投影、悬停转正和分阶段翻转入场，B 的像素 READ/WRITE 与容量淘汰粒子。倾斜图片按真实投影形状命中；主动移出与容量淘汰采用不同效果。

这是未签名的测试版，Windows 视觉结果尚未验证。源截图坐标不可用，入场从托盘附近浮卡开始。[一次完整验收卡](../../docs/windows-acceptance-0.1.2.md)已合并必须实机确认的内容，无需零散重复测试。详见[实现与验收](../../docs/windows.md)。
