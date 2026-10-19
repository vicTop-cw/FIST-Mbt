# Round 19 报告 · 守卫 selftest 基线 + 工作树 清整 扫描 + issue_scan 精度量化

- 日期：2026-10-19
- 目标：`[打磨，寻虫，修复，验证，清整，推进]` 组合模式，全程用 fist-mbt，善用其能力，注意并发 agent
- 轮次：19 / 256

## 结果摘要

并发 agent 未提交 `src/server/server.mbt`（HEAD 仍 `d010592`），BUG-327 part 2 继续阻塞；BUG-332 余 2 仍在并发 WIP。转独立寻虫/清整，两件产出：

1. **工作树 清整 扫描发现 `E：` 目录**：全角冒号（U+FF1A）路径下的 `E：/temp/moon-nightly` = **294.9 MB / 236 文件** 完整 moon-nightly 工具链，路径错乱（Windows 路径被写成全角冒号）、未被引用、真实 moon 未受影响。按不可逆操作纪律出「方案 + 预案」留确认，**不擅删**。
2. **issue_scan 精度量化**：src 全量 **9925 命中中 72.7%（7219）为编译期已保证/子串近似噪音**（`match-exhaustive` 1513 是 100% 假阳性——MoonBit 编译器强制穷尽；`unused-variable` 4259 / `long-function` 1447 为子串近似）。上报 **BUG-333**。

## 资源消耗

- 守卫 selftest 19 项复跑（跳过并发 WIP 3 项）
- `git status --ignored` + `temp/` 枚举 + `E：` 目录递归盘点
- `issue_scan dir=src max_findings=100`（9925 命中全表精确求和验证）
- `gen_plugins.py` 1 次（BUG-333 入库后重生成）+ `check_plugin_sync` 复核
- grep 验证：`moon-nightly` / 全角冒号路径拼接 / `abort` / `File::open` / `Float`
- **未跑 `moon test --target js`**：避免与并发 agent 的 WIP 构建竞争（R17 实测 1338/1338，未变更 `.mbt` 源码，故不需要重跑）

## 任务分配记录

| 环节 | 执行者 | 结果 |
|---|---|---|
| selftest 基线复跑 | lead 直接 | 18 绿 / 1 红（`check_py_stdout_encoding`，并发 WIP 预期红） |
| 工作树 清整 扫描 | lead 直接 | 发现 `E：` 294.9MB 孤立 moon-nightly 安装 |
| `E：` 根因与影响定位 | lead 直接 | 全角冒号路径事故、gitignored/未跟踪/未引用 |
| issue_scan 精度量化 | lead 直接 | 9925 命中，72.7% 噪音，匹配 `match-exhaustive` 编译器强制证据 |
| BUG-333 上报 | lead 直接（`report_bug`） | OPEN（medium），编号 BUG-333 |
| 插件重生成 | lead 直接（`gen_plugins.py`） | exit 0，`check_plugin_sync` PASS |

## 遗留风险

1. **`E：/temp/moon-nightly` 294.9MB**：路径错乱（全角冒号）的孤立安装。当前 gitignored（`temp/` 规则）、未跟踪、未引用，不影响发布与 CI。**待用户/指挥官确认后删除**（预案：`Remove-Item` 三层 `E：`、`E：/temp`、`E：/temp/moon-nightly`；如需 CI nightly fmt 对齐，`moon` 分钟级可重装）。
2. **BUG-333（issue_scan 精度）**：本轮只量化+上报，未修——`src/server/issue_scan_wbtest.mbt` 并发 WIP，动 `issue_scan.mbt` 默认行为会撞其 WIP 测试。修复方案见记忆条目。
3. **CI 上 `check_py_stdout_encoding` 作业 2/3 步红**（诚实口径）：ci.yml L148 `--selftest` exit 2、L150 `--all` exit 1；L149 默认面绿。**根因 = BUG-332 余 2（`fist_mbt_mcp_client.py` / `ns_route_probe.py`）完全在并发 agent 一侧**，我修完可动的 8 处后无法再进。并发 agent 补完这 2 处即转绿。
4. **BUG-327 part 2 仍阻塞**：`src/server/server.mbt` / `src/server/issue_scan_wbtest.mbt` 仍 M。语义级寻虫能力（`ocr_scan` fail-closed）仍缺——头号阻塞。
5. **`dist/fist-mbt.js` 未重建**：当前工作树构建会打进并发 agent 未提交代码，不合法。

## 后续建议

1. 并发 agent 提交后立即：
   - 接 BUG-327 part 2（恢复真实寻虫闭环）
   - 补 BUG-332 余 2
   - 重建 `dist/fist-mbt.js`
2. BUG-333 修复（在 issue_scan_wbtest 收口后）：默认关掉三高噪音项 + 剩余 low 项挂 `confirmed=false` 要求 run_check 复核后才 report_bug。
3. 建议把 `E：` 目录（294.9MB）纳入 `temp/` 之外的一次性清整：确认后删除。给守卫族加一条元规则：**新脚本/新安装若构造 Windows 路径必须用 ASCII 冒号 `:`**，防全角冒号事故复发。

## 超额内容

- 清整扫描揭示了 `.gitignore` 的 `temp/` 规则**意外兜住了**全角冒号路径（任意层级匹配）——否则 `E：/` 会被 `moon publish` 公开出去。这是守卫族的隐性健壮性，值得在 memory 里留一笔。
- issue_scan 的 9925 命中本身是「判据可用性」度量：守卫族在「不绿」方向很强（BUG-329/330 都是抓守卫假绿），但在「不红过头」方向缺护栏（BUG-333 是抓守卫假红）。两个方向都要门。

## 来源

- 并发 WIP 状态：`git status --porcelain`（8 项 M）
- 清整发现：`git status --ignored` + `git check-ignore -v "E：/temp/moon-nightly/bin/moon"`（命中 `.gitignore:29` `temp/`）
- issue_scan 数据：`mcp__fist-mbt__issue_scan dir=src max_findings=100`（scanned_files=129, total_findings=9925）
- BUG-333 账本：`memory/bugs.md`
- 提交：`5c84fce`
