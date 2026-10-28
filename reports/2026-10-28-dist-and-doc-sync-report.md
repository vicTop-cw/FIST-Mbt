# `dist/` 刷新 + 一源四态收口

> 2026-10-28 · Lane CP

---

## 结论

| 项 | 结果 |
|---|---|
| **`dist/` 刷新** | ✅ **成功**（内容面 **3/3** 探针全过，非仅 mtime）|
| **部署判据** | 改前 **FAIL 2 条** → 改后 **FAIL 1 条**，仓内快照 **`[FRESH]`** |
| **一源四态** | **改了 3 处**（README.md ×2、README_EN.md ×1）；其余 2 面已被并发 lane `80d3a07b` 同步 |
| **全量守卫** | `check_tools_sync` **PASS** ｜ `gen_plugins` **OK（分组和 177）** ｜ `check_plugin_sync` **PASS** ｜ `check_battery_count_doc` **PASS** |
| **残留 FAIL** | 1 条（运行产物时间面落后 **21 分钟**，**内容面 3/3 全过**）—— 并发期固有 |

---

## 证据

### ① `dist/` 刷新（硬要求①：必须验证内容面）

```
1) moon build --target js --release cmd/cli   rc=0  0 errors
2) 注入 ESM shim                              rc=0  patched
3) 拷贝到 dist                                5945828 字节
4) check_dist_snapshot.py 自证                 rc=0
   内容面：3 条探针全部有调用形
   （omega_orphan_of_archived_parent / strip_plan_annotations / omega_enabled）
```

**⇒ 不是「mtime 变新」，是 3 条语义探针都在新产物里找到了调用形。**

部署判据前后对比：

| 面 | 改前 | 改后 |
|---|---|---|
| VAL 运行产物(debug) | `[FAIL]` | `[FAIL]`（见 §3）|
| 「部署副本」旧位 | `[INFO]` | `[INFO]` |
| **仓内快照 dist/** | **`[FAIL]`** | **`[FRESH]`** ✅ |
| `_release/` | `[INFO]` | `[INFO]` |
| **违规总数** | **2** | **1** |

### ② 一源四态（硬要求②：四处一起核）

| # | 面 | 实测 | 状态 |
|---|---|---|---|
| ① | `server.mbt` 头注释 | 177 tools | ✅ 已被 `80d3a07b` 同步 |
| ② | `README.md` | **174 → 177**（2 处）| 🛠 本笔修 |
| ③ | `README_EN.md` | **130 → 177**（1 处）| 🛠 本笔修 |
| ④ | `docs/deliverable.md` | 177 个 | ✅ 已被 `80d3a07b` 同步 |
| ⑤ | 插件态 | 4 宿主 / 64 文件 / 177 工具 | ✅ 已被 `80d3a07b` 同步 |

**分组标题数字之和 = 177（18 组）** —— 这是 `gen_plugins` 的校验口径（比 `check_tools_sync` 更严），PASS。

### ③ 修改清单

```
README.md      174 个 MCP 工具 → 177 个 MCP 工具   （第 11 行、第 58 行）
README_EN.md   130 tools       → 177 tools         （第 41 行）
dist/fist-mbt.js                                   （refresh_dist.py 生成）
```

**未动**：`AGENTS.md`（按派单要求避开）；`server.mbt`（已被别人同步）。

---

## 分析：`dist/` 与运行产物的关系 —— 它到底影响谁

**R25 的结论仍然成立**：用户实际跑的是 `_build/js/<profile>/.../cli.js`
（PATH 垫片 → `serve-launcher.cjs` → 它），**`dist/` 不参与运行路径**。

**那为什么 `dist/` 还要刷？** 因为它的角色是**发版快照**：

```
dist/fist-mbt.js  ← install.ps1 -Source 的来源
                  ← 「发版快照该停在发版那一刻」的前提是「发版时刷过」
```

**⇒ 若长期不刷，下次发版会拿一个几周前的产物当发布包** —— 那时它就从「快照」变成「陈旧」。

所以判据把它按**硬门**（非 informational）守住是**对的**，
而 `_release/` 按 informational 也是对的（它是 `build_release.ps1` 现场生成的，本就该停在发版点）。

**两者的差别不是「谁更重要」，是「谁在被消费时会被重新生成」**：
`dist/` 靠人工刷新 ⇒ 必须硬门盯；`_release/` 每次发版现生成 ⇒ 不该盯新鲜。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | **残留 1 条 FAIL（运行产物落后 21 分钟）**：`_build/js/debug/.../cli.js` mtime 18:08，源码 `server.mbt` 18:29 —— **内容面 3/3 全过**，仅时间面落后。根因是并发 lane 在我构建后又改了源码。**任何一次刷新都会在几分钟内重新落后** ⇒ 按派单要求不反复重试，**等所有 lane 收口后由最后一次统一刷新消除** |
| **R2** | **`80d3a07b` 的「全量同步」并不全**：它改了 AGENTS / deliverable / scoring_rubric / 插件态，但**漏了 README 两处、README_EN 一处**（README_EN 甚至停在 130，比 174 更旧）。**⇒ 「全量同步」这个 commit 标题本身值得警惕**——判据（`check_tools_sync`）当时应该能抓到，但它 PASS 过一次（并发中间态） |
| **R3** | `check_tools_sync` 与 `gen_plugins` **校验口径不同**（前者核声明形状，后者核分组数字之和）——本单两者都跑了才放心。**建议在任何「工具数同步」单里强制两个都跑** |
| **R4** | 我未改 `server.mbt` 头注释，因为它已被同步；但**若未来有人只改 README 不改头注释**，两个判据会给出不同结论 |

---

## 建议入档位置

**无需新开 bug** —— 残留那 1 条是并发期固有状态，非缺陷。

**判例候选**：
> **判例：「全量同步」的 commit 标题 ≠ 全量。**
> `80d3a07b` 标题写「174 → 177 全量同步」，实际漏了 README 两处、
> README_EN 一处（后者甚至停在 130）——而 `check_tools_sync` 曾一度 PASS（并发中间态）。
> **⇒ 一源四态必须「逐面点名核对」，不能靠「我改了 AGENTS 就算全量」。**
> **并且：`check_tools_sync` 与 `gen_plugins` 口径不同，两者都要跑。**

**同族**：与判例-29「机制格 ≠ 实现路径格」一脉 ——
本条是「**改了几个面 ≠ 改了所有面**」。

---

**提交**：`31dade7e`（chore(docs)）+ `e3aeefcb`（chore(dist)）。
