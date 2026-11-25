# T0r84 · Node 版本门报告（`dist/fist-mbt.js serve` 在 Node<24 的明确拒绝）

- 日期：2026-11-25
- 任务：T0r84（ns=`autoplan`，assignee=`atomcode`，created_by=`human_steward`，priority=高）
- 任务源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:12-13`
- 性质：只读盘点 + 最小改动；不可逆操作未执行
- 工作树：dirty（他方 WIP 在场）⇒ 全部 git 操作仅限 scoped `-- <路径>`

---

## 一、结论摘要

| 格 | 结论 | 证据 |
|---|---|---|
| 病根确认 | **成立** | `dist/fist-mbt.js` 顶部只有 ESM require 垫片，无版本门；Node<24 时先崩在 `node:sqlite`（`ExperimentalWarning` 后列读取为空/报错），用户看到的是栈而非指引 |
| 门的落点 | **注入产物的前言**（不是 MoonBit 源码） | `src/server/server.mbt:29` 是模块顶层 `SqliteStore::new()`，ESM 求值序下任何 cmd/cli 源码内的门都晚于它；npm/DSH 启动器已有 ≥24 门（`packaging/dsh/launch-mcp.mjs:44-51`），缺口正是裸 `node <bundle> serve` |
| 阈值真源 | `toolchain.json` 的 `"node": "24"` | 逐字读回；Python 侧 `MIN_NODE_MAJOR = 24` 与其同源生成 |
| 行为两向 | **实测通过** | 合成真跑：22→rc=1、23→rc=1、24→rc=0、25→rc=0（本机 Node v25.2.1） |
| 提示可读性 | **三行中文含升级指引** | 首行「需要 Node.js >= N（当前 X）」，后两行含 `winget install OpenJS.NodeJS.LTS` |
| 判据上锁 | **`--selftest` 42 格全绿，RC=0** | 含 B5 门档 15 格 + 变异对照（改坏阈值必红） |
| 真产物验收 | **通过** | `_build/js/debug/build/cmd/cli/cli.js` 已带门且 `node ... version` rc=0 → `FIST-Mbt v0.3.15` |

**一句话**：门已落在产物前言并被判据锁死；发布快照 `dist/fist-mbt.js` 仍是旧版无门（见 §四缺口）。

---

## 二、改动清单（tracked，共 3 文件）

| 文件 | 改动 |
|---|---|
| `scripts/patch_esm_main.py` | 新增 `SHIM`(90B) 与 `NODE_GATE`(492B) 两个独立符号、`GATE_MARKER="FIST_MBT_MIN_NODE_MAJOR"`、`MIN_NODE_MAJOR = 24`、`node_gate_present()`；`patch()` 改为幂等 strip/reinject（`:147` 写 `SHIM + NODE_GATE + body`） |
| `scripts/check_esm_bundle_runnable.py` | 新增 `KIND_GATE_MISSING`(:174)、`injector_gate_major()`(:319)、`gate_static_present()`(:330)、`_simulate_gate()`(:345)、`gate_before_import()`(:423)；`bundle_checks()`(:428) 接第三档；自检 42 格 |
| `scripts/README.md` | 自述同步：17 格 → 42 格 + B5 档位说明（J10 要求自述==实现） |

**为什么门排在垫片之后**：`SHIM` 本身就是一条顶层 `import`（`import { createRequire as _cr } from 'node:module'`）。
本轮实测踩出判据口径错误——最初写成「门早于全部 import」对真产物**恒红**（垫片自身即 import）。
正确判据：**门早于垫片之后第一个 import**（即产物自己的依赖图先求值）。已按此行修正（`:401-427`）。

---

## 三、观测读数（本任务实测，非抄数）

### 3.1 门的两向（合成 `process.versions.node` + 真 node）

```
gate-sim-blocks-22    : rc=1   fist-mbt: 需要 Node.js >= 24（当前 22.11.0）。
gate-sim-blocks-23    : rc=1
gate-sim-allows-24    : rc=0
gate-sim-allows-25    : rc=0
```

变异对照：把 `FIST_MBT_MIN_NODE_MAJOR` 从 24 改成 25 ⇒ 24.0.0 由 rc=0 变 rc=1（锁会红，非恒绿）。

### 3.2 自检与真产物

```
python scripts/check_esm_bundle_runnable.py --selftest
  → SELFTEST OK (42 cells) / RC=0
    诊断读数：cmd/cli rc=0,OK ｜ cmd/commissar GATE_MISSING ｜ cmd/main OTHER_CRASH ｜ tests/smoke GATE_MISSING
node _build/js/debug/build/cmd/cli/cli.js version
  → FIST-Mbt v0.3.15   rc=0
_build/js/debug/build/cmd/cli/cli.js 顶部：
  import { createRequire as _cr } from 'node:module';
  const require = _cr(import.meta.url);
  const FIST_MBT_MIN_NODE_MAJOR = 24;
  if (Number((process.versions.node || '0').split('.')[0]) < FIST_MBT_MIN_NODE_MAJOR) { ... }
```

`cmd/commissar` / `tests/smoke` 报 `GATE_MISSING`：这两份 `_build` 产物**本轮未被 patch**（无门属预期，
patch 只作用于目标 bundle）；`cmd/main` 的 `OTHER_CRASH` 是既有读数、不在本单范围。

### 3.3 与既有面的边界

| 面 | 状态 |
|---|---|
| npm / DSH 启动器 | **已有** ≥24 门（`launch-mcp.mjs:44-51`）⇒ 本单不重复 |
| 安装器文档线 | **已有** 提示（`install_onecmd.ps1:48`、`install.sh`） |
| `upgrade_core.mbt` §8 | **先例**：「node < 24 直接拒绝」文案口径参照 |
| 真实产物带门 | **仅** `_build/js/debug/build/cmd/cli/cli.js`（CI `release.yml:121` 亦只 patch `cmd/cli`） |

---

## 四、缺口与风险（需 owner 定夺，本单不执行）

1. **`dist/fist-mbt.js` 发布快照仍无门**（顶部仅 SHIM，无 `FIST_MBT_MIN_NODE_MAJOR`）。
   合法刷新面只有 `scripts/refresh_dist.py`，而该脚本要求 WIP 已全部提交 ⇒ 当前脏树不可刷。
   **附带事实**：该快照本就落后 `moon.mod`（版本面 0.3.11 vs 0.3.15，`check_dist_snapshot.py` 现判红，
   另有 8+ 条描述串在 dist 未命中）⇒ 刷新会一并带上这些差异，须单独审阅。
2. **`dist/patch_esm_main.py` 副本落后**（与 scripts 版 DIFFER，无门）。
   但 zip 打包走 `scripts/` 源（`e2e_mirror_install.py:85`、`build_release.ps1:58` 均 `scripts/patch_esm_main.py`）
   ⇒ 不影响分发面；建议下一次 `refresh_dist` 时同步。
3. **`agent` 子命令尚不存在**（`plan:19` P0 待建）⇒ 任务文字里的「agent 启动路径加 engines 检查」**无实体可改**。
   本次只覆盖 `serve` 这一半。
4. **本机无 Node<24**：门的两向靠合成对照实证，真机 <24 复现不可得（诚实标注）。

---

## 五、资源消耗

- 改动：3 个 tracked 文件（`patch_esm_main.py` +~75 行、`check_esm_bundle_runnable.py` +~180 行、`scripts/README.md` 一段）。
- 验证：`check_esm_bundle_runnable.py --selftest` 三发（每发实跑 node，最慢一发 ~5 分钟）；门探针合成模拟若干次。
- 未跑：全仓 `moon test`（本单只改 Python 判据/注入脚本，不动 `.mbt` ⇒ 无编译面）。

---

## 六、来源

- 任务条目：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:12-13,19-21`
- 落点依据：`src/server/server.mbt:29`（模块级开库）、`cmd/cli/main.mbt`、`subcmd.mbt`、`upgrade_core.mbt:28`
- 阈值真源：`toolchain.json`（`"node": "24"`）
- 缺口边界：`packaging/dsh/launch-mcp.mjs:44-51`、`scripts/blackbox/install_onecmd.ps1:48`
- 探针/输出：`temp/gateprobe/`（已清）、`temp/selftest_final.txt`（42/42）
