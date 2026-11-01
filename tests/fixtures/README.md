# 共享历史行为用例

`history.json` 由 Swift `SharedHistoryChecks` 和 C# `SharedHistoryChecks` 直接读取；两端不保留各自复制的用例。测试仅生成临时合成文件，不读取用户历史或截图。

容量固定为 8。写入从游标起先找空槽，再找未固定槽；B 的写入标记显示真正的下一可写槽。全部固定时返回 `full`，托盘、游标和历史入槽计数不变，已经归档的文件保留，由界面提示未入槽。

固定随历史保存。旧历史缺少固定字段时按全部未固定读取；主动移出和文件缺失清理固定状态。固定文件的新版本继承固定并替换原槽，不移动游标；普通文件新版本继续按写入规则入槽。混合选择执行“固定”，全部已固定的选择执行“取消固定”。

每项用例包含：

- `initial`：依次入槽的截图别名。
- `steps`：插入、固定、取消固定、移出、重新加载，或模拟旧格式与文件缺失。`path` 用于两个版本引用同一文件。
- `expected`：从新到旧的记录、8 个槽位、固定集合、游标、累计成功入槽次数、最后一次插入结果与替换记录、下一可写槽。

运行方式：Mac 使用 `bash scripts/macos-background-check.sh`；Windows 使用 `scripts/windows-check.ps1`。Windows 核心部分也可通过 `dotnet run --project apps/windows/Jieliu.Checks -c Release` 跨平台执行。

共享数据约束历史行为；菜单、键盘、渲染和系统集成仍由各平台分别验证。2026-10-29 临时移除两端的固定保护时，两端都在 `skip-pinned-slots` 用例失败；恢复后重新通过。
