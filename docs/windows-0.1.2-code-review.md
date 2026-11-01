# Windows 0.1.2 代码审查

审查日期：2026-10-16。源码基线：`4d21e85`。范围：连续截图、A/B/C 切换、关闭动效时的选择、退出动画和状态清理。

结论：建议先修复以下 3 项，再进行完整体验验收。没有发现足以确认的死锁；发现了误选路径、特定输入顺序下的异常退出路径，以及关闭系统动画时的残留风险。本次没有修改应用源码、重打安装包或启动前台窗口。

## 1. [P2] 连续截图淘汰图片后，松开鼠标仍提交过期选择

位置：[TrayWindow.cs:148](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L148)、[TrayWindow.cs:458](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L458)。

按住一张已经选中的图片时，`Down` 把它保存在 `selectOnRelease`。此时新截图使历史达到容量并淘汰该图片，`Model.Receive` 虽然会从当前选择中剔除它，但 `Refresh` 没有取消待提交的鼠标选择。松开鼠标后，`Select` 会把已不存在的图片 ID 加回去，并可能清除其他有效选择，导致选择状态与可复制、拖出的图片不一致。

还有一条异常路径：预先多选“即将淘汰的旧图”和“仍存活的图”，让后者成为 anchor；不按修饰键按住旧图，收到新截图并淘汰旧图，再按 Shift 后松开鼠标。此时 `a >= 0`，但 `b == -1`，循环访问 `ordered[-1]`，抛出 `ArgumentOutOfRangeException`。事件处理没有本地捕获，应用也没有注册统一的 Dispatcher 异常处理。

证据：静态事件链已核对；隔离的 C# 状态复现得到 `a=0, b=-1` 和上述异常。尚未通过 Windows 鼠标事件实机复现。

修复建议：历史变化时取消失效的 `selectOnRelease` 和相关按下状态；提交选择前再次确认目标仍存活；范围选择同时校验两个索引。补充“按下→淘汰→松开”及其中途按 Shift 的回归。

## 2. [P2] C 飞入截图遮住旧图，却允许点击穿透到旧图

位置：[TrayWindow.cs:374](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L374)，绘制顺序见 [TrayWindow.cs:298](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L298)。

C 会把飞入中的截图画在最上层，但只有 `!flying` 才把它加入命中列表。下层旧图仍在命中列表中。因此连续截图期间，点击或双击新图与旧图重叠的可见区域，会选中或预览被遮住的旧图；拖动也可能拖出旧图。这不是透视几何算法不准确，而是视觉遮挡和交互遮挡不一致。

证据：用项目实际 `LayerPose.Contains` 验证同一点可同时处于新旧图内；按当前命中注册规则，顶部绘制对象为新图，命中对象却为旧图。尚未执行 Windows WPF 点击复现。

修复建议：飞入图片也参与前后顺序的命中判断。若落位前不允许操作，则它应阻断下层点击；若允许操作，则返回当前可见的新图。补充重叠区域的选择、预览和拖出目标测试。

## 3. [P2] 运行中关闭 Windows 系统动画，可能留下静止粒子与读写提示

位置：[TrayWindow.cs:192](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L192)，相关绘制见 [TrayWindow.cs:267](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L267)、[TrayWindow.cs:312](https://github.com/abelguan02/jieliu/blob/4d21e85/apps/windows/Jieliu.Windows/TrayWindow.cs#L312)。

`MotionEnabled` 同时读取应用设置和 `SystemParameters.ClientAreaAnimation`。关闭应用内动效会触发 `Changed → Refresh`，清空粒子状态；但运行中关闭 Windows 系统动画没有对应的清理订阅。下一次动画 tick 仅停止计时器并请求最后一帧，已有 `ghosts` 和 `bufferArrivals` 仍在。

B 的移出粒子绘制没有受 `MotionEnabled` 保护，可能在最后一帧停住，直到其他事件重绘或窗口收起；关闭自动收起时尤其明显。读取/写入提示仍直接读取 `bufferArrivals`，而关闭动效后不会进入移除该状态的绘制分支，因此提示也可能持续存在。C 的退出图层有同类冻结风险。

证据：静态核对了系统动画读取、计时器停止、状态清理和绘制路径；未执行 Windows 设置切换。因此这是明确的清理路径缺口，不声称已经观察到实机残留。

修复建议：将“关闭有效动效”的处理统一为清空临时效果、将过渡收敛到终态、重绘一次、停止计时器；应用设置和系统动画变化都调用它，并在释放窗口时注销系统事件。补充入场、移出两种动画进行中关闭系统动效的回归。

## 已核对的正常路径与限制

- 切换 A/B/C 时，`Refresh` 会清空入场、移出粒子和 ghost，以及样式相关的位置缓存。本次没有发现此路径会继续绘制上一种样式粒子的直接证据。
- 关闭应用内动效时，`Refresh` 会清理粒子，`RefreshVisibility` 会让展开窗口直接到达终态。该路径与关闭 Windows 系统动画不同。
- C 的透视命中使用逆变换后的图形，而非只检查外接矩形；主要问题在飞入时没有参与遮挡判断。
- 没有进行帧率或 Windows UI 压力测量，因此不能承诺连续截图一定不卡顿，也不能把核心测试通过当成体验验收通过。

## 本轮后台验证

现有 `Jieliu.Checks` 全部通过：C 投影、命中数学和关键帧；B 粒子轨迹与时序；动画中间帧、反向中断、终态和零时长；历史容量、覆盖与持久化；文件监听、重名、写入延迟和失败重试。

另外在 `/private/tmp/jieliu-review-012` 运行隔离状态复现，确认重叠命中规则返回旧图，以及过期范围选择的负索引异常。该程序只调用核心数学及复现选择分支，不是 WPF 集成测试。

测试有效性实验：仅在临时目录的 `Motion` 副本中把 `Running` 的 `&&` 改为 `||`，运行现有测试，按预期在“Collapse must terminate exactly at hidden geometry”处失败；随后恢复副本。说明终态检测确有断言保护，但不能覆盖上述界面事件交错。

现有测试缺少 `TraySurface` 的“连续接收→按下/松开”“动画中切换样式”“应用/系统分别关闭动效”事件交错验证。Windows 离屏渲染和真实交互本轮均未执行。无需现在让用户逐项代测；先修复并补齐后台回归，再把剩余体验差异合并进已有的完整验收流程。
