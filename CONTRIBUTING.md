# 本地开发与贡献

macOS 实现位于 `apps/macos/`，Windows 实现位于 `apps/windows/`。视觉参考位于 `design/`，平台行为说明位于 `docs/`。

在仓库根目录执行 `bash scripts/macos-background-check.sh` 验证 macOS 改动；该入口固定使用 `--offscreen-check`，不打开可见窗口。修改构建或资源路径后另运行 `bash scripts/build.sh`。Windows 使用 `scripts/windows-check.ps1` 执行核心回归、构建与离屏检查。核心库可跨平台执行 `dotnet run --project apps/windows/Jieliu.Checks -c Release`；交叉编译通过不等于 Windows 界面验收通过。

macOS 的 `bash scripts/check.sh` 和 Windows 检查脚本的 `-Gui` 模式会打开窗口；运行前须取得用户当时的空闲确认。

截图相关测试使用合成素材与临时目录。不要提交个人截图、缓存、应用包、签名证书或本地凭据。新依赖与素材须保留各自许可证。

行为变化需同步对应平台文档；平台尚未验证的功能应明确标注。提交尽量围绕单一改动，记录验证结果。

历史行为变更同时更新 `tests/fixtures/history.json`，Swift 与 C# 检查直接读取这份共享数据。[用例契约](tests/fixtures/README.md)说明固定、空槽与持久化规则。Windows CI 复用 `scripts/windows-check.ps1` 执行核心、构建和离屏检查；真实桌面检查仍需另外验收。

源码许可证尚未确定，当前文档不构成对外开源授权。
