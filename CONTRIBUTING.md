# 本地开发与贡献

macOS 实现位于 `apps/macos/`，Windows 实现位于 `apps/windows/`。视觉参考位于 `design/`，平台行为说明位于 `docs/`。

在仓库根目录执行 `bash scripts/check.sh` 验证 macOS 改动；修改构建或资源路径后另运行 `bash scripts/build.sh`。Windows 使用 `scripts/windows-check.ps1`，加 `-Gui` 执行 Windows 桌面检查。核心库可跨平台执行 `dotnet run --project apps/windows/Jieliu.Checks -c Release`；交叉编译通过不等于 Windows 界面验收通过。

截图相关测试使用合成素材与临时目录。不要提交个人截图、缓存、应用包、签名证书或本地凭据。新依赖与素材须保留各自许可证。

行为变化需同步对应平台文档；平台尚未验证的功能应明确标注。提交尽量围绕单一改动，记录验证结果。

源码许可证尚未确定，当前文档不构成对外开源授权。
