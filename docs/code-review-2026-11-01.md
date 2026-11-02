# 截留 1.1.3 全应用代码审查

审查日期：2026-11-01。原始审查确认 **4 项 P2 问题**，未发现有充分证据的 P0/P1 问题；审查阶段仅做检查和验证，未修改产品代码或安装应用。

后续修复状态：以下四项已在 `codex/fix-1-1-3-review` 分支修复并加入回归，详见文末。以上审查正文保留为原始发现，不代表修复后的当前状态。

## 基准与范围

- 实际审查提交：`0e5cb75b2b6b74e2a01ef9c6c1560997caf473de`，分支 `claude/project-code-review-16da34`。
- 审查使用 1.1.3 对应工作区，未将仍为 1.1.1 的主工作区作为基准。以下问题位置链接固定到审查提交，便于核对修复前的代码。
- Mac 源码和 `/Applications/截留.app` 均为 **1.1.3 / build 10**。同一提交的 Windows 源码版本仍为 **0.1.6**；文档已说明新增功能尚未更新便携包，因此不将版本差异列为缺陷。
- 覆盖：双端截图监听、归档与历史持久化、固定槽位、选择/复制/拖放/预览、A/B/C 布局及动效、设置/首次引导/关于与赞助资源、启动流程、测试、构建打包和 CI。
- 全程采用后台检查，没有激活应用、打开可见窗口、接管键鼠或进行系统权限交互。

## 需要处理的问题

### 1. [P2] Mac 首次引导更改目录会提前启动收纳

位置：[main.swift:30](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/macos/Sources/Jieliu/main.swift#L30)，相关调用位于 [OnboardingView.swift:101](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/macos/Sources/Jieliu/OnboardingView.swift#L101) 和 [AppModel.swift:123](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/macos/Sources/Jieliu/AppModel.swift#L123)。

全新用户在“准备开始”页选择归档目录后，`chooseDestination()` 无条件触发 `onRestart`，后者直接调用 `startWatching()`。此时用户尚未点击“开始收纳”，`onboarded` 仍为 false，但新截图已经会被监听、移动归档；关闭引导窗口也不会停止该监听。首次引导约定的开始边界因此失效。

证据：完整静态调用链确认，未操作真实目录选择窗口。这是新增独立引导流程中的问题。Windows 已在 `RestartWatcher()` 检查 `Onboarded`，不受此项影响。

建议：目录变更仅重启已经运行的监听器，首次启动由“开始收纳”明确触发；补测首次更改目录、关闭引导和点击开始三个状态。

### 2. [P2] 双端试截页隐藏采集错误，失败时持续提示用户截图

位置：[OnboardingView.swift:68](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/macos/Sources/Jieliu/OnboardingView.swift#L68)、[OnboardingWindow.cs:65](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/windows/Jieliu.Windows/OnboardingWindow.cs#L65)。

用户首次拒绝目录访问、接入目录无法监听或归档目录不可写时，底层已将错误写入 `lastError` / `LastError`，但试截页只根据历史总数判断“等待/成功”，没有读取错误字段。Mac 会持续转圈，两端都会继续提示“截一张试试”；试截页也没有返回配置的按钮。用户必须自行跳过引导，再打开设置查找原因，重复截图无法解决实际故障。

证据：双端监听错误上报与引导渲染调用链均已核对。这是新增试截流程的问题，现有引导检查仅覆盖正常等待和成功布局。

建议：试截页显示本轮启动/采集失败的原因，并提供返回配置或重试入口；错误解除后再恢复等待状态。无需增加常驻解释文字。

### 3. [P2] Windows 监听启动失败后，重新选择同一目录不能恢复接入

位置：[CaptureWatcher.cs:73](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/windows/Jieliu.Core/CaptureWatcher.cs#L73)、[Program.cs:75](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/apps/windows/Jieliu.Windows/Program.cs#L75)。

启动时目录暂不可用，`Start()` 捕获目录创建或监听器初始化异常后仍启动 worker 并正常返回。调用方随即把该实例和路径记为成功启动；目录恢复后，用户在设置中重新选中同一路径保存，`RestartWatcher()` 又因路径未变而直接返回，不会重新建立监听器。如果没有可用的目录监听器，worker 会一直等待不存在的事件。

证据：用链接当前 Core 源码的隔离控制台程序，在临时路径放置同名普通文件阻止目录创建，然后恢复目录并新增图片，结果为 `errors=1`、`captures=0`、`watchers=0`。相同路径的重启被阻断由调用方静态控制流确认。复现不依赖 WPF 或系统事件权限。此项在 1.1.3 之前已存在。

用户目前可以退出重开，或先换到其他目录再换回来恢复；并非永久丢失能力。建议明确向调用方返回监听启动失败状态，允许用户重选相同目录后重新初始化，无需引入泛化自动重试机制。

Mac 的目录变更会直接重建监听器，没有 Windows 的相同路径提前返回问题。

### 4. [P2] 自定义暂存路径时，干净工作区的 Mac 通用构建会失败

位置：[build.sh:13](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/scripts/build.sh#L13)，相关：[package-local.sh:12](https://github.com/abelguan02/jieliu/blob/0e5cb75b2b6b74e2a01ef9c6c1560997caf473de/scripts/package-local.sh#L12)。

设置 `APP_OUTPUT` 指向仓库外的暂存应用并启用 `UNIVERSAL=1` 后，脚本只创建应用目录，却把架构中间产物复制到尚不存在的仓库 `dist/`。干净 checkout 会在第一次复制时报错。正式发布脚本强制使用通用构建，也会遇到此路径组合；本地 DMG 脚本同样直接向未创建的 `dist/` 输出。

证据：隔离临时目录中用 fake Swift 执行真实构建脚本，退出码 1，错误为 `cp: dist/Jieliu-arm64: No such file or directory`。未执行真实签名或发布。现有打包检查预先创建 `dist/`，并把构建脚本替换成空桩，因此无法覆盖。此项在 1.1.3 之前已存在，当前已安装的 arm64 包不受影响。

建议：明确创建输出目录，或把架构中间产物放入独立构建目录；增加“无 dist + 自定义 APP_OUTPUT”的脚本回归。

## 原始审查阶段的验证结果与边界

| 平台/范围 | 本轮结果 |
| --- | --- |
| Mac 1.1.3 源码 | 固定入口 `bash scripts/macos-background-check.sh` 通过：模拟打包与入口检查、14 个共享历史用例、5 组核心检查、应用构建和全部离屏回归。 |
| Mac 已安装 1.1.3 | 使用同一脚本传入 `/Applications/截留.app/Contents/MacOS/Jieliu`，全部离屏回归通过。首次受限运行在 AppKit 注册阶段 SIGABRT；获工具审批后在沙箱外重跑通过，未将前次失败判成产品缺陷。 |
| Mac 发布完整性 | 版本/build/应用标识与源码一致；严格签名校验通过；版本 ZIP 中全部 8 个应用文件与安装包逐字节一致；赞助图片和字体许可证与源码一致。ZIP SHA256 与发布记录一致：`a24fe48d368176aa10a1cbf7621633a9e0e488dc6fe546e37cc787314cfbb14f`。 |
| Windows 核心 | 已使用本地 .NET SDK 在 Mac 后台运行，全部核心回归通过。受限环境第一次运行中目录事件检查失败；在获工具审批的沙箱外运行通过。 |
| Windows 应用 | 交叉编译通过，0 警告、0 错误；没有运行 Windows WPF 或原生窗口检查。 |
| 隔离缺陷复现 | Windows 无监听器恢复路径、Mac 自定义输出目录打包失败均已复现。 |

**引导测试缺口已通过变异实验确认：** 在临时源码副本中删除 Mac “开始收纳”按钮的 `start()` 调用，保留页面切换和布局，原后台脚本仍以 0 退出，所有检查通过。这说明当前测试不能发现“进入试截页但根本没有开始监听”。临时源码和独立构建缓存已清理，产品源码未变。

未验证：双端真实跨应用拖放、系统焦点/快捷键路由、权限弹窗与拒绝后恢复体验、登录启动、混合 DPI/多显示器，以及 Windows WPF 实机行为。Mac 前台系统集成和 Windows 实机验证不能由离屏或交叉编译结果替代。

若后续修复，优先补齐开始边界、错误状态、失败监听器重新初始化和干净打包目录的后台测试。剩余人工验收可合并为一次流程：全新引导更改目录但不开始 → 确认尚未收图 → 开始并制造一次目录错误 → 从提示恢复 → 完成试截 → 检查托盘选择、固定、复制、拖出与重启保留；Mac 和 Windows 分别记录结果。

## 四项修复与回归结果

修复代码提交：`9e53083`（打包）、`f5b8f7c`（Mac）、`b0ca559`（Windows）。工作区和上面的审查基准相同，分支为 `codex/fix-1-1-3-review`。未改变产品版本，未替换 `/Applications/截留.app`，未更新 Windows 便携包。

1. **开始边界：** Mac 目录选择交给同一模型方法保存；首次开始前不触发监听，明确开始后才允许目录变更重启。引导开始动作同时更新试截基线。新测试在旧逻辑下实际失败（更改目录触发监听），修复后通过。Windows 的原有开始门禁也由实际会话测试覆盖。
2. **失败反馈与恢复：** 两端试截页均采用错误优先状态，显示原因和「返回配置」，失败时不显示完成按钮；重新开始后可继续试截。采集错误独立于历史/设置错误，重试及成功收图不会抹掉其他错误。Mac 的恢复断言曾实际失败，修复后通过；Windows 新 WPF 回归通过真实按钮事件验证返回配置、开始和完成，并覆盖成功后再次失败及长错误文本。
3. **监听失败重试：** Windows 初始化失败会清理部分已创建的监视器并上报失败，不记录为运行成功。原 Program 的串行监听生命周期移到实际使用的 `CaptureSession`，核心回归直接验证该路径：首次门禁、部分资源释放、同路径恢复、成功归档和正常监听去重。旧实现下新测试实际失败，修复后完整核心回归通过。
4. **干净工作区打包：** 通用构建与本地 DMG 写入前创建输出目录。回归移除空构建替身，执行真实 build/local/release 脚本，仅模拟外部编译、签名、公证及镜像工具。旧代码出现四个预期失败，修复后全部通过。

本轮已通过：Mac 固定后台入口的完整回归、14 个共享历史用例及核心检查，新增引导行为回归，中英文长错误页离屏渲染与人工看图；Windows 完整核心回归、客户端交叉编译（0 警告/0 错误）及 Windows CI 原生 WPF 离屏回归；打包回归、差异空白检查及独立代码复审。

用户明确授权公开推送后，已推送 `codex/fix-1-1-3-review`，并完成 [Windows CI 41370218032](https://github.com/abelguan02/jieliu/actions/runs/41370218032)。验证提交为 `cd3dde8da99aed4ecd335a3c9bbc136eed68451f`，结果成功。日志确认新增的监听初始化失败与同路径恢复检查、真实 Back/Start/Done 按钮、成功后再失败的错误优先状态、长错误滚动、恢复及其他错误保留均通过；原有核心和 WPF 回归也全部通过。Windows 构建 0 警告、0 错误。没有合并分支或发布安装包。

Mac 无窗口的 SwiftUI HostingView 不暴露按钮 AX 子节点，因此 Mac 测试验证实际模型/引导动作与离屏布局，未将其描述为真实鼠标点击验证；Windows 新原生测试已在 CI 中执行实际按钮事件，未显示窗口或注入系统键鼠。

真实窗口、权限弹窗、登录启动和跨应用拖放仍未进行本轮前台复验；本轮未占用前台，也未修改用户截图、历史或偏好。
