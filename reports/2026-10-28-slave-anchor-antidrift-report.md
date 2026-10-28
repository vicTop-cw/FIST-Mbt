# 副机入口锚点：从「修行号」到「改指法」（2026-10-28）

## 一、起因：尺子红了 11 处，全是行号漂移

`python scripts/check_slave_task_list.py` 裸跑 rc=1，报 **11 条 B3**（内容级记号不在锚点那一行）：
`GUARD-01/02/03`、`WT-04`、`POLISH-03` 指认的 `.github/workflows/ci.yml` / `scripts/run_guards.py`
行号，被这两份文件后来的插入行整体推走（`ci.yml` 前段每轮加 guard 步骤、`run_guards.py` 电池表每轮加 `case`/`gated`）。

## 二、第一轮修完立刻复发 —— 说明「修行号」不是解法

11 处逐条改回真行号（`:288→:311`、`:294→:317`、`:300→:323`、`run_guards.py:158→:194`、
`run_guards.py:315→:448`、`run_guards.py:523→:669`、`ci.yml:435→:458`、`:436→:459`、
`:122→:145`、`:195→:218`、`:490→:513`）。

改完再跑：`run_guards.py:669` **又红了** —— 期间另一 agent 往该文件插了一段注释。
这与本仓判例同族（判例-29「机制格 ≠ 实现路径格」）：**问题不在那 11 个数字，在「指行号」这个指法**。

## 三、改指法：整份文件 + 记号（新判定面 B6）

`ci.yml` / `run_guards.py` 里的 12 处指认，从 `文件:行（记号）` 改成：

- `` 文件`（`记号`） `` —— 记号在**整份文件**任意一行出现即算命中；
- `` 文件`「逐字引文」 `` —— 引文在整份文件里必须逐字存在。

行号漂移不再影响指认，而记号仍由尺逐字核对（找不到 ⇒ **B6 红**）。

**这不是放宽**，两条反向对照锁住它：

| 对照 | 断言 | 为什么必须有 |
|---|---|---|
| `B6b` 记号在别行也不误红 | `src/a.mbt`（`gamma`），gamma 在第 4 行、锚点说第 2 行 ⇒ rc=0 | 证明「抗漂移」是真的 |
| `B6` 整份文件不含记号必红 | `src/a.mbt`（`absent_tok`）⇒ rc=1 | 证明它没有被调松成「只要文件在就绿」 |

只测「会红」的锁分不清「抗漂移指认」与「把尺调松」——所以两格必须成对存在。

## 四、顺手补上一个真漏洞：D4

改完发现 D1/D2/D3 只核 `结构级` / `内容级` / `分布` / `行数`，
而文首那行 **`文件级在场 14 条` 从来没有一把尺核过** —— 实测当时已是 **16 条**，尺照样 PASS。
这正是本尺开头自述要治的「声明滞后」形状，只是漏在第四个数上。

补 `D4` 后变异对照实测：把真清单改成「文件级在场 15 条」⇒ 尺当场点名红；
`D4b`（自述写对不误红）保证它不会永远红。

## 五、读数（全部由尺现算，非手抄）

| 项 | 改前（尺实算） | 改后（尺实算） |
|---|---|---|
| 结构级锚点 | 58（其中 11 条失配） | **46** |
| 内容级锚点 | 27 | **29** |
| 文件级在场 | 14（**无人核**） | **23** |
| 失配 | 11 | **0**（rc=0） |
| `--selftest` | 18 格 | **22 格**（A×3 / B×7 / C×4 / D×6 / E×2） |

同步面：`scripts/README.md` 该尺条目（B 族 5→7、D 族 4→6、总数 18→22）
⇒ `python scripts/check_selftest_inventory_doc.py` 由 `violate 3 条` 转 **`INVENTORY_SYNC=clean`（59 条逐一对表）**；
`check_battery_count_doc.py` / `check_doc_surface.py` / `check_text_control_chars.py` 均 PASS（本单未新增脚本、未动 CI）。

## 六、遗留风险（明写）

1. **B6 的粒度是整份文件**：若将来 `ci.yml` 里出现**同名步骤**，指认会退化（任一命中即绿）。
   当前记号取的是逐字步名 / 逐字引文，唯一性够用；一旦出现重名，须回到「行号 + 就近锚定」并接受漂移维护成本。
2. **易漂文件清单是手工认定的**（`ci.yml` / `run_guards.py`）。别的高频文件若也每轮插行，应按同一判据扩列。
3. 本单只改「认领入口 + 它的尺 + README 条目」，未动业务代码、未改 CI、未碰账本 `memory/bugs.md`。

## 七、复现

```bash
python scripts/check_slave_task_list.py            # rc=0 PASS
python scripts/check_slave_task_list.py --selftest # SELFTEST OK（22 格）
python scripts/check_selftest_inventory_doc.py     # INVENTORY_SYNC=clean
```

## 八、追记（并发提交归属，2026-10-28 12:3x）

本单一共动了 5 个文件，最终落成**两笔**提交：

| 文件 | 落点 | 说明 |
| --- | --- | --- |
| `scripts/check_slave_task_list.py` | 501c4929 | 本单主体（B6 + D4） |
| `docs/2026-10-20-slave-tasks.md` | 501c4929 | 12 处指认改指法 + 文首自述对齐 |
| `reports/2026-10-28-slave-anchor-antidrift-report.md` | 501c4929 | 本报告 |
| `scripts/README.md` | **9518c590** | 被并发提交带走（`+5`，含本单的「22 格」条目） |
| `scripts/run_guards.py` | **9518c590** | 被并发提交带走（`+8`，含本单的 `--selftest` 说明注释） |

即：**同一笔提交里混进了不属于它的两处改动**（AGENTS.md「判例-11 单次并发索引事故」同族）。
事后已用 `git show 9518c590:scripts/README.md | grep` 与 `git show 9518c590:scripts/run_guards.py | grep`
逐字核实**内容确实落盘**（「22 格（A×3 / B×7 / C×4 / D×6 / E×2」与「22 格合成树」各命中 1 次），
不存在「被带走但内容丢了」的情形。

**这暴露的不是谁手滑，是流程缺口**：本单已按纪律用 `scripts/commit_scoped.sh`（前置暂存面必须为空 +
逐个 add + `git commit -F msg -- <paths>`），但那只护住**我自己那一笔**；在别人正在跑的窗口里，
我的工作树改动会先被别人的 `git add` 扫走——**防护面在「写」那一侧，不在「谁提交」那一侧**。
⇒ 可行改进（未单独立项）：并发窗口内改 `scripts/README.md` / `scripts/run_guards.py` 这两份热点文件时，
改完立刻自查 `git status --porcelain -- <file>`：若显示 clean 而自己并未提交，说明已被扫走，
应立即核实内容（`git show <HEAD>:<file> | grep <记号>`）并在下一笔里记清归属，而不是以为「丢了」重写一遍。
