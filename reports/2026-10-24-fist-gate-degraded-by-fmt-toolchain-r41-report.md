# `fist-gate` 在 Windows 上永久 DEGRADED（BUG-388 的连带面）——诊断与两条出路

日期：2026-10-24（R41）｜环境：Windows 11 / moon 0.1.20261016 / Node v24.17.0｜基线：main `a3c517d6`

## 结果摘要

`python scripts/fist-gate.py` 在**任意分支、任意干净树**上都返回 **rc=2**，而它打印的六行里只有一行是
`DEGRADED`，其余全 `PASS`：

```
PASS merge_markers: 跟踪面无未解决冲突标记（扫描 1395 个 git 跟踪文件）
DEGRADED fmt: 格式化器未预热（缺 _build/wasm-gc/release/format/）——在一次性副本上跑 `moon fmt` 预热后再判；判据自身不预热（门链必须只读）
PASS build: rc=0, 0 errors
PASS ps_encoding: 9 .ps1 ASCII/BOM ok
PASS store_path: 11 store files ok
PASS whisperer: SELFTEST OK (…)
```

聚合逻辑是 `gate()` 里的 `rc = max(rc, c)` ⇒ 一个子检的 2 把整门顶成 2。
而电池（`scripts/run_guards.py`）把 `fist-gate.py` 登记为 `expect=0` ⇒ **电池在 Windows 上永远红一条**，
且这条红**不是本仓代码的问题**，是 BUG-388（`moon fmt --check` 本机跑不完）的连带面。

## 证据

| 项 | 读数 |
|---|---|
| main（`a3c517d6`） | `fist-gate.py` rc=**2** |
| 我的分支（R41） | `fist-gate.py` rc=**2**（同一原因，非本支引入） |
| 缺什么 | `_build/wasm-gc/release/format/`（矿灯子检按存在性判"格式化器预热没"） |
| 本仓既有仲裁 | `AGENTS.md`：**本机 `moon fmt --check` 不可用（BUG-388）**，判它请用 `scripts/check_fmt_gate.py`：`0` 干净 / `2` 不可测 / `1` 真差异；**格式门权威面以 CI（Linux nightly）为准** |
| 后果 | 本地 `fist-gate` 永远 2 ⇒ 要么被人无视（门失效），要么电池永远红一条（掩盖真红） |

## 两条出路（都不改"格式门谁说了算"，需 owner 选一条）

**方案 A（把 fmt 子检交给既有三档判据）**
`fist-gate.py` 的 fmt 检改为调用 `scripts/check_fmt_gate.py`：
- 判 0（干净）⇒ 本子检 0；
- 判 1（真格式差异）⇒ 本子检 **1**（真红，照旧）；
- 判 2（不可测）⇒ 本子检同样标为不可测，但 `gate()` 聚合把"不可测"与"失败"分开计数，输出形如
  `gate: 5 PASS / 1 NOT-MEASURED (fmt: BUG-388) / 0 FAIL`，退出码 **0**，并明写
  "本机 fmt 面不可测，权威以 CI Linux 为准；本地未测 ≠ 已过"。
- 好处：本地门可用，且**没把不可测说成通过**（用 NOT-MEASURED 计数显式化）。
- 代价：退出码契约从「2=有任何不可测」收紧为「2=连聚合都做不到」，需同批改 `run_guards.py` 的
  expect 与 `scripts/README.md` 的 rc 说明。

**方案 B（保留 2，把它登记成本机预期）**
`run_guards.py` 把 `fist-gate.py` 一格从 `case(...)` 改为
`expected("fist-gate.py", 2, "本机 fmt 面不可测（BUG-388）⇒ 整门 DEGRADED 是诚实结果；CI Linux 面 fmt 可测时应为 0")`。
- 好处：一行改动、零语义变更。
- 代价：电池读数变成**平台相关**（Linux 0 / Windows 2），而"预存红"的语义是"同一真源同一读数"，这点会破。

**建议：A。** B 把平台差异塞进"预存红"语义格，会让"预存红"不再可信；A 把"未测"显式化成第三个计数，
既保住"不许把未测当绿"，又让本地门可用。但 A 改退出码契约（不可逆面）⇒ 按金条四，执行权留 owner。

## 遗留风险

1. 若走 A，需同步：`run_guards.py` 期望值、`scripts/README.md` rc 契约说明、CI 是否跑电池。
2. 本机 `_build/wasm-gc/release/format/` 缺失的**更深原因**仍归 BUG-388（工具链），A/B 都只是处置。
3. 本轮**未改** `fist-gate.py` 或电池期望——证据与方案在此，裁决后一行可落。

## 来源

- 触发：R41 电池复跑（本支除该格外全绿；该项在 main 上同样为红）
- 同族：BUG-388（本机 `moon fmt --check` 不可用）、`scripts/check_fmt_gate.py` 三档口径、BUG-394（进料形状错配）
