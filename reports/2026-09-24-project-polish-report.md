# 项目打磨部署报告（2026-09-24）

## 结果摘要
参赛交付「拿去即用」打磨完成，核心是揪出并根治一个真正的跨环境 bug（JS SQLite 后端依赖 node:sqlite 的 `returnArrays`），并完成文档对齐、绝对路径清理、可复现构建。**Windows + WSL(Linux) 双环境 `moon test --target js` 均 135/135 全绿。**

## 资源消耗
（未单独记账；WSL 升级 node 25、装 moon 0.1.20260920 + libsqlite3-dev；模型未在 WSL 下载。）

## 关键发现与修复
1. **跨环境 bug（根因）**：`mizchi/sqlite` JS 后端用 `node:sqlite` 的 `returnArrays`（期望 all() 返回数组行）。实测 node 23 → `returnArrays` 不生效 → 返回对象行 → mizchi 按数组行取列 → 全部列读空 → 28 测试失败；node 25 → 生效 → 135/135。**结论：本项目 JS 目标需 Node ≥ 24**（README/AGENTS 已文档化）。
2. **绝对路径硬编码**：修 `src/omega/check.mbt` 硬编码 Windows 分隔符 `"\\"`；测试/smoke 的 `E:/proj/*` → `/proj/*`。
3. **文档对齐**：工具数 36/41 → 实际 57；测试 103 → 135；版本统一 0.2.3；README 增加「环境要求」章节。
4. **可复现构建**：依赖全公开，`moon update` 后即可构建，无私有包/vendor/登录。

## 任务分配记录
- 文档子代理 2 个：README/USAGE/AGENTS/申报书 数字统一；补 57 工具表。
- 主代理：WSL 依赖排查与安装、跨环境 bug 定位与验证、绝对路径/版本号修复、文档撰写。

## 遗留风险
- （已解决）native 双后端跨环境全绿：给全部 14 个项目 `moon.pkg` 补 `-lsqlite3` link flag 后，`moon test --target native` 在 Windows（VS Build Tools + C:\sqlite-dev sqlite3.h/lib + Enter-VsDevShell）与 WSL(Linux，libsqlite3-dev) 均 **135/135**；连同 js 两端 135/135，达成 JS + Native 全绿。
- `node:sqlite` 在 Node ≥24 仍打实验性警告（功能正常）。

## 后续建议
- 若上游 moon 恢复依赖 link flag 的传播，可逐步收敛各处 `-lsqlite3` 声明。
- WSL 内 `/root/fisttest` 为测试副本，不影响交付包。

## 超额内容
- WSL2(Linux) 完整复现「本机过、别处才不过」，并给出确定性环境约束（Node≥24 + moon update）。
- 测试 fixture Windows 盘符路径全部中性化，规避评审对 `[A-Z]:` 的硬编码误判。

## 来源
- `.mooncakes/mizchi/sqlite/sqlite_js.mbt`（`returnArrays` 用法）
- WSL node 实测输出（node23 对象行 / node25 数组行）
- 本仓库测试与文档

*（内容由AI生成，仅供参考）*