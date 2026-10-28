# Windows 客户端实现与验收

## 实现契约

本轮按用户确认方向实现 Windows 11 原生客户端：C# / WPF，.NET 10；默认 B 帧缓冲、取景框胶囊、中文。A 标尺 / C 图层、仅系统托盘图标、English 和自动收起均可在设置中调整，入口与展开样式独立保存。

核心库 `Jieliu.Core` 不依赖 Windows UI，可在 macOS 上运行文件与历史测试。`Jieliu.Windows` 管理 WPF、系统托盘、屏幕、原图拖放和设置。`Jieliu.Checks` 是无需第三方测试框架的回归程序，失败以非零退出码结束。

0.1.1 补齐可中断的胶囊展开/收起、截图浮卡入槽、记录重排、移出归档、C 图层展开、悬停抬升、选中蚂蚁线、RGB 指针呼吸与预览过渡。时间由单调时钟计算，窗口按当前过渡尺寸变化，收起完成后才隐藏极简模式入口。收起或关闭窗口时停止动效计时器。设置中的「界面动效」默认开启，并遵循 Windows 系统动画设置；关闭动画直接落到最终状态。

0.1.2 按 HTML 分工：C 使用 `rotateX(-16deg) rotateY(-48deg)` 的平面投影、悬停转正放大 1.12、24/128 间距的堆叠与展开（按窗口宽度归一化）、1.15 秒抬起/翻转/落位、700ms 容量淘汰和 220ms 主动移出。HTML 没有指定 perspective 距离，因此没有虚构相机透视；点击区域随投影四边形变化。B 使用原图采样的最多 576 个像素单元，320ms 扫描、错峰贝塞尔 READ 汇聚、480ms WRITE 扫描，以及容量淘汰的粒子归档。主动删除不套用容量淘汰粒子。

入场的源浮卡位于托盘附近，不能等同于 HTML 演示中已知的屏幕截图矩形。运行时间使用单调时钟；切换样式或关闭动画会清理旧效果，最终仍显示原图。诊断导出只保存渲染阶段和耗时/环境，不保存截图内容及路径。

## 截图接入

0.1.3 修复过期鼠标选择及 Shift 范围越界、C 飞入图片点击穿透，以及运行中关闭 Windows 系统动画时的粒子/提示残留。样式切换同时取消未完成的按下状态；未绘制就被淘汰的入场记录也会清理。核心选择规则已加入跨平台回归，真实托盘事件状态与绘制组合已加入 `--render-check`，以可控时钟和系统动画输入覆盖连续截图、切换、关闭及恢复动效。

- 通过 Windows 已知文件夹 API 找到截图目录，处理 Pictures 重定向；可在设置中另外指定接入与保存目录。
- 启动前已有图片作为基线，不自动批量归档；监听与补充扫描接入之后新建或改变的图片。
- 支持 WPF 原生解码的 PNG、JPEG、BMP、TIFF。先等待文件版本稳定、排除写入占用并成功解码，再归档和通知界面。
- 接入文件夹是用户选择的图片来源，无法仅凭图片确认它是否由截图工具产生；放进该目录的普通图片同样会收纳。仅位于剪贴板的截图不收集。
- 同名文件使用唯一新名称，不覆盖原归档；归档失败保留源文件并在设置显示错误。
- 新截图采用鼠标所在屏幕回退：Windows 落盘文件不能可靠给出截图来源屏幕。尚未实现截图区域与来源显示器的严格对应。

## 交互与存储

8 槽环形历史、Ctrl/Shift 多选、Ctrl+A、Ctrl+C、方向键、Space / 双击预览、Delete 从托盘移出、Esc 收起。拖放为复制，提供原文件路径；单张图片另外提供原分辨率位图，PNG 同时提供原始 PNG 字节。

Delete、清除历史条目和环形淘汰均不删除归档文件。历史、写指针与偏好以 JSON 原子替换保存在 `%LOCALAPPDATA%\Jieliu`。每个屏幕独立窗口，自动出现使用不激活展示，用户点击才请求焦点；混合 DPI 布局需真机验证。

## 开发命令

在根目录使用 .NET 10 SDK：

```powershell
dotnet run --project apps/windows/Jieliu.Checks -c Release
dotnet build apps/windows/Jieliu.Windows -c Release
dotnet run --project apps/windows/Jieliu.Windows -c Release
powershell -ExecutionPolicy Bypass -File scripts/windows-check.ps1 -Gui
powershell -ExecutionPolicy Bypass -File scripts/windows-build.ps1
```

macOS 可以用 `EnableWindowsTargeting` 交叉编译，但不能执行 WPF。Windows 检查脚本默认执行 `--render-check` 离屏检查：不创建可见窗口、不使用鼠标键盘/剪贴板，覆盖 C 纹理投影与命中区域、B 各阶段像素和结束残留。`-Gui` 额外运行 `--self-check`，会显示测试窗口，必须先确认电脑空闲。当前这两类 Windows 检查均未在本机执行，不能记作通过。

## 发布前真机检查

- Windows 11 x64 启动、退出、二次启动不重复运行；系统托盘菜单可访问。
- Win+Shift+S 自动保存、Win+PrtScn、自定义目录、OneDrive 重定向、持续大图写入及睡眠恢复。
- 拖入微信、Figma、邮件、资源管理器，确认原图字节及多选顺序；剪贴板被其他程序占用时可恢复。
- 单屏、双屏、100%/150%/200% 混合缩放、拔插显示器、任务栏各位置、全屏应用与虚拟桌面。
- 仅系统托盘模式收起后没有残留窗口或不可见悬停区域；自动出现不抢键盘焦点。
- 对照 `design/concepts.html` 核验视觉、选中框、层叠与动画。0.1.2 已实现 C 旋转投影和 B 像素粒子，但 Windows 视觉运行尚未验收，不能宣称逐像素一致。
- 动效专项：展开途中移开并重新进入、快速连续截图、收起期间来图、切换仅托盘模式、删除多张、动画设置关闭/开启、预览关闭后自动收起，确认无闪跳或残留热区。

当前没有 Windows 实机执行结果。便携包采用自包含运行时，未做 Authenticode 签名，不是正式发行包。后续安装器、自动更新、开机启动与 ARM64 实测另行补齐。

本轮人工验收合并为[一次截图整理操作卡](windows-acceptance-0.1.6.md)，不要求用户逐项接力代测；保留旧版 ZIP 和应用身份/配置位置，0.1.6 使用独立版本目录与包名。包内 `BACKGROUND-CHECK.cmd` 可运行无需 SDK 的 Windows 离屏检查。0.1.4 支持 B 动画与托盘展开期间选择可见图片，选中位置不影响下一张的写入槽位。

0.1.5 同步修正双端视觉对齐：B 的时间/读写状态靠卡片右边缘；C 摘要按实际字体宽度居中，标签按当前相邻图层距离限制宽度，摘要与标签错开显示；A 尺寸文字限制在所属列内。原生字体、标签间距和实际 B 时间绘制检查纳入 `--render-check`。Windows WPF 检查需在 Windows 执行，Mac 交叉编译不等于已验证实际显示。

0.1.6 修复格式异常退出监听、限制缩略图最长边并避免放大小图，键盘移动提取到核心规则并纳入连续扩选/淘汰回归。实际 WPF 解码尺寸、原图尺寸、坏图报告及 FileFormatException 后继续接收的检查均包含在 `--render-check`，尚需 Windows 执行。

## 参考

- [微软 WPF 文档](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)
- [非 Windows 系统的 Windows targeting](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/netsdk1100)
- [Windows 截图工具](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots)
