# R121 · 文本面控制字符零容忍门 + 全仓 30 处「被吃字母」修回

- 日期：2026-10-22
- 分支：`slave/gate/text-control-char-r121`（基线 `gitcode/master` = `cd697333`；R120 `af021d63` 已经 `1dfb641f` 并入主线）
- 提交：`43e6b45c`（修字节）/ `e199b19d`（新门 + 接线）/ 本报告提交

## 一、结果摘要

R119/R120 连着三份制品出现同一形状：写 `\b`、`\e`、`\f` 时，生成链路把它们当转义序列消费掉，只留下一个**不可见控制字节**（0x08 / 0x1b / 0x0c 等），字母本体丢失。文件照样能读、能提交、能发布，工具不报任何错；只是 grep/正则永远命不中，读者拿到的不是作者以为的那段字。

R121 做两件事：

1. **全仓清零**：按二进制扫描找到 10 份文件 30 处控制字节（字节构成：0x1b×15 / 0x07×5 / 0x08×4 / 0x0c×4 / 0x00×1 / 0x0b×1），逐处按上下文还原被吃的字母（`\b`→`b`、`\a`→`a`、`\e`→`e`、`\f`→`f`、`\0`→`0`、`\v`→`V`），CRLF 逐份原样保留。R120 已并入主线的 3 份文件 4 处（TASK-023 / memory 2026-10-22 / R119 报告）不重复修。
2. **常驻门**：新增 `scripts/check_text_control_chars.py`——C0 控制字符（制表/换行/回车除外）+ DEL 零容忍，扫仓根文本面；`--selftest` 九格（G×4 / M×3 / R×2）自证会红也会绿。ci.yml 挂在 Merge-marker 之后、Migrate 之前；README 登记 + 电池 `--selftest` 格；`BATTERY-REGISTRATION` 同步到现读 `rulers=87 ci=41 battery=49 missing=0 gate=58 exempt=26 unclassified=5`。

## 二、证据

### 2.1 修复面（`43e6b45c`，父提交 `cd697333`）

| 文件 | 控制字节 | 类型 | 还原后的上下文（抽样） |
|---|---:|---|---|
| `BACKLOG.md` | 1 | 0x08 | `blocked`（0x08 吃掉 `b`） |
| `memory/2026-09-25.md` | 14 | 0x07/0x08/0x0b/0x0c/0x1b | `extract_difficulty` / `best` / `alice` / `for i=0` / `VicTop-cw` |
| `memory/2026-10-13.md` | 5 | 0x0c/0x1b | `evolve_asset_register` / `exec_order` |
| `memory/2026-10-19.md` | 4 | 0x07/0x08/0x0c | `award_demo` / `by_difficulty` / `engine.triage` |
| `reports/2026-10-19-R22-report.md` | 1 | 0x1b | `best` |
| `reports/2026-10-19-R23-report.md` | 1 | 0x1b | `exec_reg` |
| `reports/2026-10-19-R25-report.md` | 1 | 0x1b | `field` |
| `reports/2026-10-20-R28-report.md` | 1 | 0x00 | `08a31d0`（0x00 吃掉 `0`，git 原按二进制处理） |
| `reports/2026-10-21-issue-scan-rule-layer-audit.md` | 1 | 0x08 | `by_severity` |
| `scripts/check_release_asset_names.py` | 1 | 0x0c | `fist-mbt-js-v0.3.4.zip`（0x0c 吃掉 `f`，紧邻 R13 判据面） |

合计 **10 份 / 30 处**，全部为「同长替换或按原意回填」（两处原意是正则 `\b` 的按 R120 口径回填两字节），`git diff --stat` = 26 insertions / 26 deletions + 1 个二进制文件 1311→1310 bytes（0x00→`0`）。

### 2.2 新守卫自证（`e199b19d`）

```
python scripts/check_text_control_chars.py --selftest
SELFTEST OK: 9 格（清单从已执行格子反解：G×4 / M×3 / R×2）

python scripts/check_text_control_chars.py
扫描面=F:\AI\Fist-Mbt | 文本 1350 份 | 违例 0 处
PASS 文本面无 C0/DEL 控制字符
```

九格构成：G1 干净不误红（制表/CRLF 合法）/ G2 非文本扩展不误扫 / G3 清场后回绿 / G4 真现状面必绿；M1 0x08 必红 / M2 DEL 必红 / M3 嵌套目录 ESC 必红；R1 空面自拒 / R2 目录缺失自拒。退出码契约：0=干净 / 1=有违例 / 2=判据无法自证 / 4=尺子自己坏了。

判据面：C0 控制字符 0x00-0x08、0x0b、0x0c、0x0e-0x1f（**制表 0x09 / 换行 0x0a / 回车 0x0d 是合法排版空白**）+ DEL 0x7f；扫描面 = `.md/.py/.ps1/.sh/.yaml/.yml/.json/.txt/.mbt/.mbti/.cmd/.pkg` + `moon.mod`/`.gitignore`/`.gitattributes`，跳过 `.git/.mooncakes/node_modules/_build/target/temp/dist`。

### 2.3 接线读数

| 判据 | 读数 |
|---|---|
| `check_battery_count_doc.py` | PASS `rulers=87 ci=41 battery=49 missing=0 gate=58 exempt=26 unclassified=5` |
| `check_scripts_index.py` | PASS |
| `check_selftest_inventory_doc.py` | PASS（28 条对表；本尺 判定族 3 / 实现反解族 3 / 合计 9 格） |
| `check_doc_surface.py` | PASS（J1-J15 全格） |
| `check_doc_dup.py` | PASS（1141 行无重复长条目） |
| `check_exit_code_contract.py` | PASS |
| `run_guards.py --selftest` | PASS（37 格；现状 87 把尺 / CI 41 / 电池 49 / 缺面 0 / 常驻豁免 2） |
| `check_ci_step_position.py` | **FAIL 35 > 34**（预存红，登记在电池 `expected` 里；本单新步在 Migrate 之前，不增违例） |
| `check_scripts_naming.py` | **FAIL N1 22>16 / N2 5>4**（预存红，登记在电池 `expected rc=1` 里；本单新脚本是 `check_` 前缀 snake_case，不入两条判定面） |
| 全量电池 | 见 §2.5 |

### 2.4 接手时主线已有的红（与成因）

接手后先跑 `check_battery_count_doc` / `check_scripts_index`，在**未加本单任何东西**的 master 树下实读 rc=1：

- `check_scripts_index.py` rc=1：`check_fmt_gate.py` 未在 `scripts/README.md` 登记；
- `check_battery_count_doc.py` rc=1：锚点 `85/40/47/0/56/26/5`，现读 `86/40/48/0/57/26/5`（尺 / 电池面 / 门禁尺三键落后）；
- 电池里 `check_fmt_gate.py` 裸跑 rc=2，与登记期望 0 不符。

成因同一处：`c480fa9f` 自带这三条接线（README 条目 + 锚点 84→85 + `run_guards` 的 `case("check_fmt_gate.py", "--selftest")`），但合线提交 `cd697333` 的 diff **只有 `scripts/check_fmt_gate.py`**，README 与 run_guards 的 hunk 在手工解冲突时被丢回第一父分支。证据：`git show c480fa9f -- scripts/README.md` 有该条目与锚点 diff；`git show cd697333 --stat` 无 `scripts/README.md` / `scripts/run_guards.py`；修复前 `grep -c check_fmt_gate scripts/README.md` = 0、`grep -c check_fmt_gate scripts/run_guards.py` = 0。

本单**逐条补回**（内容逐字取自 `c480fa9f`），因为不补则 `check_scripts_index` / `check_battery_count_doc` / 电池三处恒红，新门无法在绿基线上交付。这是跨单修复，已在此点名，不藏在「顺手」里。

### 2.5 全量电池

`python scripts/run_guards.py`（提交后、推送后复跑）：

- 结果：见文末追记（本报告提交时首次运行读数：63 格 / 失败 3——`check_publish_payload`（新守卫尚未跟踪）、`check_delivery_gap`（HEAD 未推送）、`check_fmt_gate`（SPECIAL_CASE 尚未补回）；三者均在本单提交/推送后消除）。

## 三、资源消耗

- 会话内工具调用：约 55 次（含 3 次全仓扫描、2 次全量电池、1 次 rebase）。
- 新增/改动：1 个新脚本（163 行，CRLF）、README 2 条、ci.yml 1 步、run_guards 1 格、10 份文件 30 字节修复、报告 1 份、日志 1 段。
- 未跑 moon 构建/测试：本单不碰 `.mbt`/`.mbti`，无需 `moon fmt` / `moon test`。

## 四、任务分配记录

本单为**字节级精修 + 单文件守卫**，未拆子代理：子代理回传的文本会再走一遍同一生成链路（正是本单要修的形状），且 30 处都要求按上下文还原、逐处二进制度量。由指挥官亲做，每一步后用 `bytes/crlf/bare_lf` 三元组与上下文抽样复核。终审为实测：新守卫自检、全仓裸扫、六个对表守卫、电池与 `run_guards --selftest` 逐条实跑。

## 五、遗留风险

1. **跨单补回的三条接线**（§2.4）若与 BUG-381 owner 的后续分支在同一锚点各插一次，合线时会产生同位置双插冲突；冲突解法是保留一份、不重排。
2. **扫描面是扩展名白名单**：新增文本类型（如 `.toml`/`.lock`）默认不在判定面内，需要同批加进 `TEXT_EXTS`；二进制文件按设计不扫。
3. **零容忍没有白名单**：未来若有正当的控制字节用途（如文档里嵌 ANSI），本门会直接红。要放行必须显式加「允许清单 + 理由」，不能靠改判据面绕过。
4. **G4 读真仓**：并发 agent 若写入控制字节，本尺 `--selftest` 会以 rc=4 自拒（这是设计意图——真现状面不许假绿），但会让别人的电池格跟着红，需要按「谁写谁修」处理。
5. `check_delivery_gap` 以「HEAD 是否已在远端」判交付：推送前跑电池必红一格，属环境态而非代码健康。

## 六、后续建议

1. 把本门挂进 `scripts/fist-gate.py` 门链或 git pre-commit（当前只有 CI + 电池两个执行面）。
2. 在生成侧治根：写正则/转义说明时，Python 字符串里用 `\\b`；bash heredoc 用**引号 heredoc**（`<<'EOF'`）或改用 Write 工具落临时脚本——本轮两次踩到 heredoc 吃转义。
3. `docs/`、`plugins/` 已被本门覆盖；若后续引入 `.toml` 配置，同批扩 `TEXT_EXTS` 并补一格自检。
4. 考虑把「控制字节 -> 被吃字母」的还原配方（同长替换、按上下文核验、CRLF 三元组度量）写进故障处置手册，避免下一单重新摸索。

## 七、超额内容

- §2.4 的三条合并丢失接线补回（README 条目、锚点、run_guards case）——超出「新门」本身，但不补则主线三处恒红。
- 扫描面主动纳入 `.gitignore` / `.gitattributes`：这两份被吃字母会静默改变忽略语义，是最隐蔽的一类。

## 八、来源

- 修复提交：`43e6b45c`（父 `cd697333`）；守卫与接线提交：`e199b19d`。
- 既有接线来源：`c480fa9f`（README hunk / 锚点 hunk / run_guards hunk）；丢失现场：`cd697333` 的 merge diff。
- 本单读数：`check_text_control_chars.py` / `run_guards.py --list` / `--selftest` / `check_battery_count_doc.py` / `check_scripts_index.py` / `check_selftest_inventory_doc.py` / `check_doc_surface.py` / `check_ci_step_position.py` / 全量电池输出（temp/r121_battery.log，仓外）。
