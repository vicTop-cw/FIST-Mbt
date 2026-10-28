# `dist/` 部署刷新报告（Lane BU）

> 2026-10-28 · 未改 `src/`；`dist/` 由 `refresh_dist.py` 重建（未手改）

---

## 结论

| 面 | 结果 |
|---|---|
| **仓内快照 `dist/fist-mbt.js`** | ✅ **已刷新到 08:46:23**（内容面 3/3 探针通过）；守卫当刻变 `[FRESH]` |
| **部署副本 `%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js`** | ⚠️ **未刷新，也不需要刷新** —— **它不是用户实际运行的产物** |
| **`check_deployment_freshness.py` 现在 PASS 吗** | ❌ **仍 FAIL，且这些 FAIL 是误报**（见 §分析 + §5） |

### ⚠️ 两条必须写清的诚实口径

**① dist 现在又落后了，但这不是刷新失败：**
```
dist/fist-mbt.js             @ 2026-10-28 08:46:23  ← 我刷新的时刻
src/server/server.mbt        @ 2026-10-28 08:50:49  ← 并发 lane 4 分钟后又改了
src/engine/dag_core_wbtest   @ 2026-10-28 08:52:38
⇒ [FAIL] 仓内快照  时间面落后 4 分钟
```
**⇒ 多 lane 并发下「dist 新鲜」本就无法稳定保持 —— 这是并发刷新的固有形态，不是刷新失败。**
**正确做法：等所有 lane 收口后由最后一次统一刷新（本报告不反复重刷）。**

**② 🔴 派单前提不成立：「用户从 PATH 拿到 31.5 小时前的旧版本」是误判。**
实测：PATH 垫片 → `serve-launcher.cjs` → `repo/_build/js/release/.../cli.js`，
**全文件 176 行里 `fist-mbt.js` 出现 0 次**。**用户拿到的已经是最新构建。**

---

## 证据

### 1. 仓内快照：刷新成功

```
$ python scripts/refresh_dist.py
[构建 release 产物] rc=0  ran 5 tasks, 0 errors
[注入 ESM shim]     rc=0
[拷贝到 dist]       5862627 字节
[自证版本一致]       rc=0  内容面：3 条探针全部有调用形
```
守卫随后：`[FRESH] 仓内快照 mtime 2026-10-28 08:46（lag=-0.1h） 内容 3/3 符号有调用形`
**⇒ 硬要求 ① 达成**（dist 08:46:23 > src 最新 08:46:13）。

### 2. ⭐ 决定性发现：部署副本已被 PATH 旁路

**PATH 垫片**：`"%FIST_NODE%" "%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs" %*`
**`serve-launcher.cjs:44,48-49`**：`const REPO = ... || 'E:\IDEProjects\AI\FIST-Mbt';`
  `{ name: 'release', file: path.join(REPO, '_build','js','release','build','cmd','cli','cli.js') }`
**⇒ 全文件（176 行）里 `fist-mbt.js` 出现 0 次 ⇒ launcher 不读它。**

**符号对拍**：

| 文件 | `omega_orphan_of_archived_parent` | 用户实际用它吗 |
|---|---|---|
| `_build/js/release/.../cli.js`（08:46 构建 5862627 B） | **3 次** | ✅ **是** |
| `%LOCALAPPDATA%\...\fist-mbt.js`（10-26，5342744 B） | **0 次** | ❌ **不是** |

### 3. 部署副本可写但我不写
`%LOCALAPPDATA%\FIST-Mbt\` **可写**（`test -w` ✅），能 `cp`。**但我没覆盖**：
它不参与 PATH 运行路径（§2）⇒ 覆盖**不改变用户拿到的版本**；且旁边 3 个 `.bak` 是历史遗留旧部署位。
**⇒ 正确做法是修正守卫目标，不是刷新它。**

---

## 分析：为什么部署副本「会过期」—— 设计缺陷，不是运维问题

**旧设计**（`install.ps1`）：`Copy-Item -Force` 一次性拷到 `%LOCALAPPDATA%`，**之后无自动更新**
⇒ 不重装就永久停在装机那一刻。
**新设计**（BUG-437 `serve-launcher.cjs`）：**每次启动直接从 repo `_build` 读** ⇒ **天然不会过期**。
**⇒ 两者并存，守卫还在盯旧的那个。**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **守卫检查的 3 个目标全部是误报**（同一个根因）：①「部署副本」`%LOCALAPPDATA%ist-mbt.js`（launcher 不读它，44.7h lag 是假的）②「release 产物」`_release/js/fist-mbt.js`（`build_release.ps1` 生成的**发布包快照**，供 `install.ps1 -Source` 用，本就该停在发版那一刻）③ 2 条 `[UNPROVABLE]` 垫片（实测执行 `.cjs`，不在判据词表内） |
| **R4** | 首次刷新因并发 lane 的 `engine_rsv.mbt:240` 顶层 `let mut`（编译错）失败；**等 ~5 分钟收口后重试成功**。`refresh_dist.py`「构建失败即中止、不留半成品」行为**正确** |

---

## 建议入档位置

**① 修正守卫目标**（Lane BU 第二段执行）：当前**每次都 FAIL，一条恒红的守卫等于没有守卫**。

**② `_release/` 应从「必须新鲜」判定里摘掉**：它是发布包快照，要求每次开发后重建与用途矛盾。

**判例候选**：
> **判例-XX：改运行路径时，守卫的检查对象也必须跟着改。**
> BUG-437 把 PATH 入口从 `%LOCALAPPDATA%\fist-mbt.js` 改到 `serve-launcher.cjs` → `_build/cli.js`，
> 但 `check_deployment_freshness.py` 仍检查旧路径 ⇒ **用户拿到最新版，守卫却报「旧 44.7 小时」**。
> **⇒ 与判例-33 是同一枚硬币的两面**：判例-33「别绕开生产路径去测」；本条「**改了生产路径后，别继续测老路径**」。

---

**只刷新了 `dist/fist-mbt.js`（经 `refresh_dist.py`）。未改 `src/`、未手改构建产物、未覆盖仓外文件。**
