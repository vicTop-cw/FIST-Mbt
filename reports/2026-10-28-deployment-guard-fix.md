# 部署新鲜度判据修正（Lane BU 第二段 · BUG-438）

> 2026-10-28 · 改 `check_deployment_freshness.py` + 两份文档格数

---

## 结论

| 面 | 改前 | 改后 |
|---|---|---|
| **launcher 实际产物** | **不存在此面** | ✅ **`[FRESH]`**（新面 3/3 符号） |
| 旧「部署副本」 | `[FAIL]` 44.7h | **`[INFO]`**（BUG-437 后非运行路径） |
| `_release/` | `[FAIL]` 9.7 天 | **`[INFO]`**（发布包快照） |
| **违规总数** | **4 条** | **1 条** |
| **`--selftest`** | 42 格 | **48 格**（新增 R×6） |

**能否 PASS**：**不能完全 PASS，但原因变对了** —— 剩下那条 FAIL 是「`dist/` 落后并发源码几分钟」，
真实且会随收口消失；三条历史误报全消。

---

## 证据

### 5 处改动

1. `RE_NODE_JS_CALL`：`.js` → `.js/.cjs/.mjs`；程序名从字面 `node` 扩到 `"%VAR%"` / `$VAR`
2. `parse_shim_target`：加 `os.path.expandvars`（`.cmd` 写的是 `%LOCALAPPDATA%\...` 占位）
3. 新增 `launcher_profiles` / `choose_bundle` / `_stat_bundle` / `launcher_faces`：从 launcher 反解 profile
   顺序 + **复刻 `statBundle` 过滤**（存在 + ≥100KB），定「实际执行哪一个」
4. `shim_faces`：垫片指向 `.cjs` 时**跟随一跳**到它加载的 `cli.js`（拿包装器评业务符号必假红）
5. `assess_face`：① `informational=True` 面只进 warns；② **`runtime-entry`/`path-shim` 不算构建缓存**

### ⭐ 变异对照（真跑）

**把 launcher 实际执行的 `_build/js/debug/.../cli.js` mtime 改到 2020-01-01**：

```
改前 [FRESH] 运行产物(debug，launcher 实际执行)
改后 [FAIL]  运行产物(debug，launcher 实际执行)     违规 1 → 2 条
恢复 [FRESH]  回到 1 条
```

**⇒ 判据确实在看用户实际运行的文件。**

**⚠️ 这一格还抓出自己的一个 bug**：首次变异只出 `[WARN] 构建缓存，按需重建`（`_build/` 命中
`BUILD_CACHE_MARKERS`）⇒ **用户实际运行的产物被当成"缓存"降级了** —— 改动 5② 由此而来。
**没真跑变异，这个 bug 会留在判据里。**

### `--selftest`

`SELFTEST OK：48 格（A×6 / D×6 / F×18 / P×6 / R×6 / S×6）`。
新增 **R×6**：`.cjs` 字面量 / `.cmd` 变量程序名 / `%VAR%` 展开 / launcher profile 顺序 /
informational 绝不进 fails / 非 informational 必进 fails（正向对照）。

---

## 分析：为什么这是最坏的判据形态

**没有判据** ⇒ 没人知道旧不旧，也没人被骗。**判据恒绿** ⇒ 假安全，至少不浪费人的时间。
**判据恒红且理由失效** ⇒ **每轮都有人追一个不存在的问题**。

**本次代价**：这个 FAIL 最近几轮被反复上报为「部署副本过期 31.5/44.7 小时」，
**每轮都在追不存在的对象** —— 而真正的判据（用户跑的 `cli.js`）**一直是绿的**。

**根因链**：`install.ps1` 一次性拷到 `%LOCALAPPDATA%`（无自动更新）→ BUG-437 把入口改到
`serve-launcher.cjs` → `_build/.../cli.js` → **判据没跟着改，继续查那个没人再写的旧文件** ⇒ 恒红。

**⇒ 与判例-33 是同一枚硬币的两面**：判例-33「别绕开生产路径去测」；本条「改了生产路径后，别继续测老路径」。

**`_release/` 为何不该判新鲜**：由 `build_release.ps1` 生成、供 `install.ps1 -Source` 用
—— **是发布包快照**，本就该停在发版那一刻。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 仓内快照仍 `[FAIL]`（落后并发源码）。**真实状态**，收口后 `python scripts/refresh_dist.py` 一次即消 |
| **R2** | `launcher_profiles` 是**保守正则解析** launcher 源码；若 launcher 大改结构，解析返回空 ⇒ 该面**消失而非误判**。未覆盖 `FIST_MBT_CLI_JS`/`FIST_MBT_PROFILE` 强制路径（已知简化） |
| **R3** | `_stat_bundle` 复刻了 `MIN_BUNDLE_BYTES = 100*1000`，launcher 改它则判据要同步（注释已标出处） |
| **R5** | ✅ **已核**：`check_tool_coverage.py` 与本脚本**互不 import**（双向 grep 均空），`run_guards.py` 各自独立注册；按提醒**未触碰它** |

---

## 建议入档位置

**账本**：新立 **BUG-438 `[judge] 部署新鲜度判据检查目标已失效`**，标 FIXED。

**判例候选**：
> **判例-34：判据必须检查「用户实际运行的那个文件」。**
> BUG-437 改了 PATH 入口，而判据仍检查旧位 ⇒ **用户拿到最新版，判据却连续几轮报「旧 31.5/44.7 小时」**，
> 每轮都有人追不存在的对象。
> **⇒ 改运行路径时「被检查对象」必须同批改；否则判据从「看不见」退化为「指错方向」。**
> **配套硬要求**：判据要能从**生产配置反解**出被检查对象（本例：从 `serve-launcher.cjs`
> 解析 profile 顺序 + 复刻 `statBundle`），而不是写死路径常量。

---

**只改判据 + 两份文档格数。未动 `run_guards.py`/`check_tool_coverage.py`/`src/`。变异实验已全部恢复原状。**
