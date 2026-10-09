截留 · Jieliu — Windows 11 x64 测试版 0.1.1

解压整个 ZIP，再运行 Jieliu.exe。请保留所有 DLL、运行时和资源文件。
无需安装 .NET SDK 或运行时。本包尚未进行 Authenticode 签名或 Windows 真机验收。

右键系统托盘中的取景框图标进入设置；左键展开。
默认中文、B 帧缓冲、屏幕顶部取景框胶囊，可分别切换 A/B/C、English、仅托盘图标。
动效默认开启：胶囊展开/收起、截图入槽、布局位移、移出归档、预览和选中虚线。
如看不到动效，检查截留「界面动效」及 Windows 设置 → 辅助功能 → 视觉效果 → 动画效果。

在 Windows 截图工具中启用自动保存，并让保存目录与截留的接入文件夹一致。
默认使用系统截图目录。只在剪贴板中的截图不接入；接入目录中的普通图片也会被收纳。
启动前已有文件不批量导入。修改已存在图片会产生新的文件版本记录。
新截图在鼠标所在显示器展开；尚不能可靠确认截图来源显示器。

Ctrl/Shift 多选；Ctrl+A 全选；Ctrl+C 复制；方向键切换；Space/双击预览。
Delete 从托盘移出并保留磁盘文件。拖出提供原文件复制，不移动原图。
托盘只保留 8 条记录，淘汰记录不会删除归档文件。

设置和历史保存在 %LOCALAPPDATA%\Jieliu。
退出：右键系统托盘图标 → 退出截留。
卸载：退出后删除解压目录；如需重置偏好，可另删除上述配置目录，勿删除自己的截图归档。

待验证：Windows 实际窗口与焦点、外部应用拖放、多屏混合缩放、截图工具各种入口。
视觉限制：已加入过渡动效，C 仍为平面错层；HTML 的完整透视和粒子尚未逐像素复刻。
源项目许可证尚未确定；Geist 字体按随附 Geist-OFL.txt 单独授权。

English: Extract the entire folder, then run Jieliu.exe. This unsigned preview bundles
the .NET runtime. Right-click the notification-area icon for Settings and select English.
Only new/changed images in the configured folders are collected. Clipboard-only captures
are excluded. Delete and history eviction keep archived files. New captures open on the
pointer's monitor. Windows GUI, drag/drop and mixed-DPI validation remain pending.
