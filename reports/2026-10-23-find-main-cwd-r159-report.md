# R159 · `find_main()` 的 CWD 依赖缺陷修复（派单给 atomcode · 指挥官终审）· 2026-10-23

## 结果摘要

`scripts/fist.py` 与 `scripts/mcp_smoke.py` 的 `find_main()` 把候选入口写成**裸相对路径**
（`_build/js/debug/build/cmd/cli/cli.js`），`os.path.exists(p)` 与返回值都按**调用方当前工作目录**解释。
后果：从仓库根跑正常，从任何其他目录跑就报「未找到构建产物」——而产物**确实在那儿**。
`fist.py` 是宿主/人工统一 CLI 网关，`mcp_smoke.py` 是 MCP 冒烟入口，这一格坏掉的样子是
「工具说没构建」，很容易被误读成「产物没建」而重跑构建。

修法（atomcode 交付，逐字审阅后原样采纳）：候选按 `_FIST_ROOT`（由 `__file__` 反推的仓库根，两文件里本来就有）
拼接后再判存在、再返回——返回值同时从「相对路径」升级为「绝对路径」，下游 `Popen([node, main, "serve"])`
不再依赖子进程 cwd 恰好是仓库根。

改动面：`scripts/fist.py`、`scripts/mcp_smoke.py` 各 2 行（共 4 增 4 删），零 MoonBit 代码、零新增脚本、零新增判据格。

## 证据

探针 `r159_probe.py`（仓外运行，cwd 故意设成 `C:\Users\Administrator`），`PROBE OK 6/6`、rc=0：

| 格 | 内容 | 读数 |
|---|---|---|
| A | **修复前**代码（主仓 `scripts/fist.py`，其 `_build/.../cli.js` 实测存在 = `True`） | `''` ← 这就是缺陷本身：产物在、找不到 |
| B | 修复后代码 + 全新工作树里放占位产物，cwd 在仓外 | 绝对路径，前缀 = 该工作树根 |
| C | 反向对照：删掉占位产物 | `''` ← 诚实的「确实没有产物」，不是冒出相对路径 |
| D | 修复后代码，cwd == 仓库根（常规用法） | 同 B，绝对路径 ⇒ 常规用法零回归 |
| E | `mcp_smoke.py` 修复后，cwd 在仓外 | 绝对路径 |
| F | `mcp_smoke.py` 反向对照（无产物） | `''` |

A 与 C 是两支不同方向的对照：A 钉「旧代码在产物存在时也会说没找到」，C 钉「新代码在产物缺失时仍说没找到」——
少了 A 就证明不了这不是「产物真没有」，少了 C 就可能把「恒返回某个路径」当修好了。

调用面实跑：`cd %TEMP% && python <工作树>/scripts/fist.py --help` → rc=0，用法正文正常打印。

家族普查（同一形状还有谁）：`grep` 到 23 个脚本引用该产物字面量，逐类看消费方式后，
其余脚本是**构造正确**的——`award_demo.py:78`、`task_challenge_verify.py:45` 一类走
`Popen([NODE, MAIN, "serve"], cwd=ROOT)`（相对路径按子进程 cwd 解释，而 cwd 被显式钉成仓库根），
`enrich_selfdrive.py:92` 一类走 `os.path.join(ROOT, MAIN)`。**只有这两支少了这层保证**。
所以本单不需要连改 23 处；但"少这层保证"这件事本身没人管，见「后续建议」。

## 资源消耗

- `moon check`：不适用——本单零 MoonBit 改动，未跑（不虚报成 0 errors 的实测）。
- Python 语法面：两份改动文件被 `python <脚本> --help` 实际导入执行成功。
- 判据面：`scripts/run_guards.py` 里 `fist.py` 标注为「统一 CLI 网关（人工/宿主调用入口），不是判据」，
  `mcp_smoke.py` 标注为「MCP 冒烟（需构建产物 + node，CI 由 run_check 面另跑）」⇒ 两脚本**本就没有电池格**，
  登记块无需改动，新增测试数为 0 ⇒ `check_test_sync` 不受影响。
- 单份面：无新增脚本文件 ⇒ `check_scripts_index` 读数不变（其预存红见「遗留风险」）。
- 占位产物只在 `temp/`（在 ignore 面）内创建并已删除，探针与占位文件不留痕。

## 任务分配记录

- 派单：`executor_run(executor="atomcode", project_dir="temp/wt-r159")`，任务包
  `temp/wt-r159-task-brief.md`，边界「只改 `scripts/fist.py` 与 `scripts/mcp_smoke.py`，不构建不提交」，
  验收标准里**点名要占位产物探针 + 反向对照**（R146 那单是我补的反向对照，这单直接写进任务包）。
- 进程 rc=0；回执之外仍以现读 `git diff` 为准（`executor_run` 的归因缺陷虽已由 R152+R156 修，纪律不变）。
- 交付内容逐行审阅：4 行改动与任务包语义一致，无越界文件，无自造验收口径 ⇒ **原样采纳，指挥官未补码**。
- 指挥官自留面：探针编写与实跑、家族普查、报告与成支（接线/终审不外包）。

## 遗留风险

1. **正确形状无人强制**：`cwd=ROOT` / `os.path.join(ROOT, …)` 这两种保证只存在于各脚本各自的写法里。
   新脚本再写一支 `os.path.exists("…/_build/…")` 裸相对路径，没有任何尺会红。这是本案的复发面。
2. `scripts/check_scripts_index.py` 预存红 rc=1（5 个未登记脚本）——与本案无关（本单未新增脚本），照例点名不代修。
3. 本单没有常驻判据，所以「修好了」这件事将来只由代码自身担保；风险 1 的尺不补，第 2 次同类缺陷还得靠人肉发现。
4. `reports/2026-10-15-capability-coverage-matrix.md` 等历史面里的轮次号与本轮取值区间重叠（同号双义），
   取号面仍无认领机制（账上既有缺口，本单不扩面处理）。

## 后续建议

- 给 `scripts/check_entry_paths.py`（BUG-93/101 那支入口搬家尺）补一条子判据：
  凡脚本里出现「以 `_build/` 或 `target/` 开头的裸相对产物路径」，其消费点必须满足
  ①`os.path.join(ROOT|_FIST_ROOT, …)` 拼接，或 ②`Popen(..., cwd=ROOT)`；两条都不满足即发红。
  并配两支反向对照（合法 `cwd=ROOT` 不误红、合法 join 不误红）+ 一支「扫描面为空必自拒」。
  归 **R161** 车道，接线归指挥官（不外包——本仓电池格与 CI 步位受棘轮尺管）。
- 文档面：`scripts/README.md` 里这两支入口的用法示例建议明确写「可在任意目录用绝对路径调用」，
  否则读者仍以为必须先 `cd` 到仓库根。

## 超额内容

家族普查（23 处引用逐类判定消费方式）不在任务包内，是指挥官为「要不要连改一片」做的判断，
结论是**不需要**，并把结论转成了「后续建议」里的判据提案。探针 6 格（含 E/F 第二支脚本）也超出任务包要求的 3 格。

## 来源

- 缺陷实测：`r159_probe.py` 格 A（产物存在但 `find_main()` 回 `''`），2026-10-23 本机 Windows。
- 修复交付：`executor_run` → atomcode，工作树 `temp/wt-r159`，分支 `slave/fix/find-main-cwd-r159`。
- 相关积累（指挥官侧记忆，不入仓）：外部执行器派单形状与终审四关、轮次取号五面查法；
  AGENTS.md「JS 可执行产物 ESM 兼容」段（`mcp_smoke.py` 入口职责）。
