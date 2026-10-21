# 2026-10-21 R23 汇报：`slave/fix/deprecated-api-renames` —— 0020 机械改名子族清零（176 条）

- 分支：`slave/fix/deprecated-api-renames`（stacked on `test-qualified-imports`(#9) → `syntax-noise-sweep`(#8) → `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0`/`T0r2`/`T0r3` 均已完成；本单挂新根 `T0r4` 走完整生命周期（publish→claim→execute→submit→verify）
- 台账：BUG-347（low，FIXED，轮次 R23）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 872 | **696** |
| 同判据 errors | 0 | **0** |
| `error_code` 20（deprecated） | 703 | **527** |
| 机械改名子族命中（to_owned / is None / Map / has_prefix / count / length / StringBuilder） | 176 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 非漂移分歧（47 份文件） | — | **0** |

改动 47 份 `.mbt`（+196/−181 行）：StringView `to_string()`→`to_owned()` 123、`x.is_none()`/`x.is_some()`→`(x is None)`/`(x is Some(_))` 20、`Map::new()`→`Map([])` 13、`starts_with`→`has_prefix` 9、`length()`→`count()` 5、`size()`→`length()` 4、`StringBuilder::new()`→`StringBuilder()` 3。零接口变更（`check_mbti_sync` 前后同 PASS，641 条声明）。

## 资源消耗

- 工具调用：约 20 次；`moon check --target js` 全量 4 次（首轮暴露 13 条 4080、次轮暴露 4 条语法错、终轮锁钉）、`moon test` 全量 2 次、moonfmt 逐文件 3 轮 × 47 份、守卫 1 轮 × 13 例。
- 本机墙钟：本单约 17 分钟。
- 返工：3 次，全部是量法/改法自身的错，不是判据不达标 —— ① `Map::new()` 直译成 `Map()`（13 条 4080，按 loc 二次修正为 `Map([])`）；② Option 改写的接收者切片 off-by-one（先在 `src/ops` 试点暴露，加"span 必以 `.name()` 结尾"的结构断言后重跑）；③ 链式接收者回溯过深产出 1 处语法错（手修 + 复跑确认）。

## 任务分配记录

- 指挥官亲自做：子族分档（机械改名 vs 类型面 vs API 契约）、`Map::new`/`is_none` 两处改法的判断、终审判据（实跑 check/test/fmt/守卫四轮）、记忆沉淀。
- 子代理：未派（177 处改写由 loc 驱动脚本一次成型 + 3 处手修，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r4` 全生命周期，连续第六轮。

## 遗留风险

1. **0020 仍有 527 条**，其中 `Json::value` 452 是最大单体：它要把 `Json` 的取值面换成索引/`as_*`，逐点判断"取不到值时怎么办"，属语义改动，不能塞进机械档。
2. **`str[:]`(42) 与 `reinterpret_as_int64`(11)** 涉及实参顺序与类型面，各自需要一轮。
3. **stacked 合并顺序**：本支依赖 #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
4. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面缺 1302 声明、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入。
5. **`atgc-old/talk.mbt` 也在改名面**（2 处 `to_owned`）：它在构建图内、被 check/test 覆盖，但目录名易被误判为归档件而漏验；本单已实跑覆盖。

## 后续建议

1. 下一单建议 **0079 implicit_impl_as_method**(63)：统一补 `pub extend T with @moonbitlang/core/debug.Debug::{to_repr}`，编译器已给出确切声明文本；它同时动 `.mbti`，需与接口面一起终审。
2. 或 **0002 unused_value**(37) + **0004 missing_priv**(11) 合成"低风险第二单"：前者加 `_` 前缀、后者收窄可见性，判据是 `check_mbti_sync` 的同步变化。
3. `Json::value` 452 先做 3–5 份文件的试点（建议 `src/server/bugreport*.mbt` 与 `src/engine/engine_circuit.mbt`），量测"是否需要引入 `get_or` 辅助函数"再决定是否批量。
4. BUG-330（Int/Int32、`? :`/`~ :`）仍待 owner 决策；本轮再次证明它是每轮拆行合并的主要噪声源。

## 超额内容（本单边界之外做了什么、为什么）

- 顺带把 `Map::new()` 与 `is_none/is_some` 两族的改法固化成可复用的结构自检（span 后缀断言 + 接收者括号平衡校验），写进 `temp/fix20.py`，避免下一轮重复踩同一个 off-by-one。
- 未做：未加任何 `warnings = "-..."` 压制、未动 `Json::value`/`substring`/`to_int64` 等语义档、未跑破坏性 `cleanup_artifacts.py`、未动 `.mbti` 拼写面、未删任何"看起来没用"的类型或函数。

## 来源

- 判据：`temp/chk15.json`（872/0，改前）、`temp/chk19.json`（698/0，改名后）、`temp/chk20.json`（**696/0**，终态，机械改名子族命中 0）、`temp/pt11.log` 与 `temp/pt12.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 中间态取证：`temp/chk16.json`（13 条 4080 的 `Map()` 误改）、`temp/chk17.json`（4 条语法错的 `is Some(_)` 误锚点）、`temp/chk18.json`（698/0）。
- 守卫：`check_pkg_imports` / `check_mbti_sync` / `gen_plugins --check` / `gen_plugins --selftest` / `check_plugin_sync` PASS；`temp/run_guards10.py` 全 13 例输出。
- 台账：`memory/bugs.md` BUG-347 + `### FIXED(2026-10-21 轮次 R23 / BUG-347)`；`memory/2026-10-21.md` R23 小节。
- 改法脚本：`temp/fix20.py`（改名 + Option 改写，含 span 断言）、`temp/fix20b.py`（`Map()`→`Map([])` 的 loc 驱动二次修正）、`temp/census20.py`（0020 子形状普查）、`temp/apply_fmt25.py`（norm 区间合并）。
- 既有结论：BUG-344（同行同码去重量法）、BUG-345（纯语法三族）、BUG-346（0025 全族 + check/test 重写 mbti 的工序）、BUG-329/330（`\\?` ICE 与拼写漂移）、BUG-32（fist.py 入口产物新鲜度守卫）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
