# 2026-10-22 · 副机 R105 · 格数自述守卫泛化 + 自锁 + 抄本逐份并入 · 报告

分支：`slave/guard/inventory-face-self-lock-r105`（基点 `gitcode/main` = `0777985e`，R104 已入主线）
改动面：`scripts/check_selftest_inventory_doc.py`、`scripts/check_upgrade_installer.py`、
`scripts/check_backlog_status_staleness.py`、`scripts/README.md`、`memory/2026-10-22.md`、本报告。
**零 `src/*.mbt` 改动**（不触发 moon fmt/info/test 面）。

## 结果摘要

R104 立的「格子计数自述 ↔ 已执行格子反解」对表尺，本轮做三件事，都由实测逼出：

1. **族名文法泛化**：`R\d+` → 「≤3 个大写字母 + 可选数字」，配三道闸——词界（前后不接字母数字）、
   `NOISE` 缩写表（`P0/P1/CI/CD/JS/…` 不算族）、行级「格/支」单位门（一行没有计数单位就不可能在这行抽到清单）。
2. **同名条目逐份并入**（原为末份覆盖）⇒ 新增判据 **X5 抄本打架**；实测把 `check_release_asset_names.py`
   的比对族数从 8 抬回 14，并当场把 6 份旧抄本的总数落差暴露在 X3 里。
3. **本尺自锁**：README 里本尺的条目永不进判定面，跳过份数打进判定面读数。

顺带把泛化抓出来的两处真失联补成实做：`check_upgrade_installer.py`、`check_backlog_status_staleness.py`
的 `--selftest` 现在都打「反解」锚点行，判定面从 **1 把尺长到 3 把尺**。

## 证据（逐条读数）

| 判据 | 命令 | 读数 |
|---|---|---|
| 本尺自检 | `python scripts/check_selftest_inventory_doc.py --selftest` | `SELFTEST OK: 25 格（清单从已执行格子反解：G / M×24）` rc=0 |
| 本尺裸跑（电池格） | `python scripts/check_selftest_inventory_doc.py` | `INVENTORY_SYNC=clean 判定族 22 条逐一对表通过` rc=0；判定面读数 `条目 586 份 / 带族计数自述 3 份 / 自锁跳过本尺 1 份` |
| 泛化前 → 后（同一条尺） | 同上，改动前后各跑 | 改动前 `判定族 8 / 实现反解族 14`（末份覆盖把 6 份旧抄本读成现状）；改动后 `判定族 14 / 实现反解族 14 / 对表合计 38 格` |
| 新抓到的失联 | 泛化后首跑 | `FATAL: X4 …check_upgrade_installer.py 文档有 3 条族计数自述，实现清单拿不到：输出里没有「反解」锚点行` rc=2 ⇒ 实测定形，不是猜的 |
| X3 实红（修文档前） | 同上 | `违例 X3 …总数自述 17/38 与实现反解合计 38 格不符` rc=1 |
| upgrade_installer | `--selftest` | `SELFTEST OK: 19 格（反解：G1×5 / G2×5 / G3×8 / RS×1）` rc=0；裸跑 rc=0 |
| staleness 自检 | `--selftest` | `SELFTEST OK: 11 格（反解：M×2 / P×2 / R×4 / V×3，族名取自已执行格子名首段首字母，不手写计数）` rc=0 |
| 退出码契约 | `python scripts/check_exit_code_contract.py` | rc=0 |
| EOL 面 | 逐文件字节统计 | 4 份改动文件 CRLF-only、LF-only=0、孤 `\r`=0（`core.autocrlf=true` 要求） |

### 本轮修掉的三处文档谎账（都是 R104 自己欠的）

- `scripts/README.md` 把整份守卫条目列表**重复了 7 遍**，R104 只同步了其中 1 份 ⇒ 6 份仍写 `十七格变异（R1×2…R8×3）`、
  6 份仍写 `十九格（R9×2）`。现 6 份同步成三十八格那份权威清单，旧单族读数改成「三十八格（族清单只在上面一处写）」。
- `check_upgrade_installer.py` 的 README 自述 18 格、实现面是 18+1（现状面那一格没进任何清单）⇒ 实现面补 `RS×1`，
  文档 7 份同步成十九格。
- `check_backlog_status_staleness.py` 的自检**总数**是 `return fails, 11` 手写常量、分组名只写在 PASS 行散文里
  ⇒ 换成 executed 列表反解，文档抄上机器可比的清单形态。

## 资源消耗

单轮会话内完成；命令 ~10 发（全部本地、无网络、无构建）；改动 4 份文件（1 份守卫 +161/-58 行、
1 份守卫 +16/-6、1 份守卫 +6/-4、README 28 行）；未跑 `moon` 面（无 .mbt 改动）。

## 任务分配记录（金条四）

- 指挥官亲自做：分流决策（本单是「尺子泛化 + 文档同步」，属轻-中任务，不发布 FIST 子任务包）、
  实测定口径（三次 `--show-face`/首跑读数决定文法与合并语义）、终审（金条八：全部读数实跑取得）。
- 不可逆动作留手：合并、backlog yaml 状态盖章、`STALE_CEILING` 下调、改名批——只出方案，不代执行。

## 遗留风险

1. `ran`/`fails` 两套自检簿记里，`check_upgrade_installer.py` 的 **分组计数仍是 `ran.append("G1×5")` 级字面量**
   ——它现在与文档对表了（文档漂移必红），但「组里真跑了几格」仍靠人守。出路：把 `j_selftest` 改成
   `cell(name, ok)` 簿记（同 staleness 本轮做法），约 20 处调用点。
2. README 的 **7 份重复列表**是结构性债务：本轮让不一致必红（X5/X3），但没做去重（去重动 586 条目、
   与 `check_scripts_index` 的登记面纠缠，属另一单）。
3. AGENTS.md 面仍未入判定面：族名→脚本归属在散文行里不是机械可定（假红比漏红更坏）。

## 后续建议

1. 立 `check_selftest_inventory_doc.py` 的「实现面必须有反解锚点」为**新写守卫的开工规范**，
   写进 `AI-DEVELOPMENT-STANDARD.md`（本轮已把 3 把尺拉进面，示范成本足够低）。
2. `check_upgrade_installer.py` 改 `cell()` 簿记（风险 1 的出路），同批把 staleness 的族名首字母映射
   从「首段首字母」升级为「整段大写缩写」并自锁。
3. README 去重单独立项（风险 2），配合 `check_scripts_index` 的 3 支未登记脚本一并收口。

## 超额内容

- 未在原计划内，但被实测逼出：`check_upgrade_installer.py` 补锚点 + README 七份抄本同步、
  X5 抄本打架判据、`check_backlog_status_staleness.py` 的 executed 反解改造。
- 未做（有意留下）：README 7 份列表去重、AGENTS.md 归属机械化、`STALE_CEILING` 下调、backlog 状态盖章。

## 预存红点名（不代修，逐一点 rc 与成因）

| 判据 | rc | 成因 | 是否本改动引入 |
|---|---|---|---|
| `check_backlog_status_staleness.py`（裸跑） | 1 | `落差 9 条 > 上限 4`；主线合并了 TASK-019/022/023 的点名 commit 而 backlog yaml 未盖章。**同一分支基点 HEAD 版同红**（实测取 rc=1） | 否 |
| `check_doc_surface.py` | 1 | J4：`scripts/README.md:220` 另写发布版本 0.3.9，真源 `moon.mod` = 0.3.10 | 否（该行未触碰） |
| `check_scripts_index.py` | 1 | `merge-prompt.txt` 未在 README 登记 | 否 |
| `check_scripts_naming.py` | 1 | N1 无角色名 20 > 上限 16、N2 连字符名 5 > 4（TASK-008 改名批未做） | 否（无新增脚本文件） |

## 来源

- 本仓 `agents.md` 金条四/五/八、`AI-DEVELOPMENT-STANDARD.md` §7 已知边界、退出码字母表（BUG-369）。
- 上一单：`reports/2026-10-22-slave-r104-selftest-inventory-doc-sync-report.md`。
- 实测读数全部来自本会话内的真实命令输出（见「证据」表）。
