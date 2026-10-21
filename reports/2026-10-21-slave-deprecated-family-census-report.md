# 2026-10-21 · 副机 R36 报告 · 0020 其余子族的文本代理量程实测（BUG-362 建议③ / T0r17 / PR #23）

- 角色：副机（Qoder Desktop agent），分支 `slave/guard/deprecated-census-families`，base = R35 的 `066e476`
- 任务包：目标=量清上一单元那把新尺能量谁、量不了谁；边界=零 `.mbt` 改动，只动族表/夹具/文档口径；回传=实测三向对照表 + 入表条目 + 自证夹具；验收=`--selftest` 全绿、真判据面 PASS、基线读数不变、守卫全套无回归
- 一句话结论：**0020 剩下五个子族里只有 `utf8.encode` 一族有可证的文本代理（判据 3 / 文本 3，盲区 0，已入表）；`Show`(8+3)、FFI `Array`(3)、隐式提升(1) 三族的弃用点在语义上，名称级普查会给出负缺口，站点并集普查会把上限逼到 1322——两种硬塞都已被实测成 rc=2 / rc=1，不是推测。**

## 1. 结果摘要

| 交付 | 内容 | 判据 |
|---|---|---|
| 族表第二条 | `Check @encoding/utf8.encode(0020 via String::to_bytes)`：`judge_marker="utf8.encode"`、`text_regex=\.to_bytes\(`、`gap_ceiling=0`、`audited` 写明三处站点与 BUG-360 的关系 | 真判据面 PASS（3/3，缺口 0） |
| 量程边界入文档 | 守卫 docstring 新增「哪些族进不了这张表（实测，不是设想）」整段；决策稿新增 §3.5 三向对照表；`scripts/README.md` 补族表现状与量程口径 | `check_scripts_index` PASS |
| 夹具补格 | `--selftest` 第 10 支「判据多于文本的负缺口」，覆盖 `evaluate()` 里**写了却从未执行过**的 `gap < 0` 分支 | selftest rc=0（10 支） |
| 账本 | BUG-362 追 `landed[R36]`（建议③ 完结），状态仍 OPEN（11 处本体待 BUG-361） | `gen_plugins --check` / `check_plugin_sync` PASS |

## 2. 实测读数（守卫与基线）

| 格子 | 读数 | 来源 |
|---|---|---|
| 三向对照（0020 全族） | `Json::value` 430/441（盲区 11）；`utf8.encode` 3/3（盲区 0）；`Show` 8+3 行 11 条 对 名称级 2、站点并集 1333；FFI `Array` 3 对 1463/953；隐式提升 1 对 32/7 | `temp/chk43.json` + 290 个跟踪 `.mbt` |
| 守卫自检 | `--selftest` 10 支各自命中指名的判据，rc=0 | 本轮实跑 |
| 真判据面 | 族表 2 条：430/441 缺口 11（上限 11）、3/3 缺口 0（上限 0）⇒ PASS，rc=0 | 本轮实跑 |
| 变异对照 | 抹掉 dump 里 3 条 utf8 判据（模拟编译器整族沉默）⇒ rc=1，点名 `src/router/star_gate.mbt +1`、`src/router/star_gate_wbtest.mbt +2` | `temp/chk42_mutated_no_utf8_judge.json` |
| 语义族硬入表探针 | 名称级 ⇒ rc=2「判据命中未被本族文本正则覆盖」；站点并集 ⇒ rc=1、缺口 1325（按 8 条那一支）/1322（按 11 条那一支） | 直读守卫 `evaluate()` 真接口，未改表 |
| 基线不变 | `moon check --target js --json` rc=0，489 诊断 / 0 errors，族分布与 R35 的 `temp/chk41.json` 逐格相同 | 本轮实跑 |
| 测试面 | `moon test --target js -j 1` → **Total tests: 1302, passed: 1302, failed: 0**（`temp/pt23.log`；rc=0 只作旁证，本仓 `moon test` rc 不可靠是已记事实，判据取计数行。本轮零 `.mbt` 改动，这一格是独立复验而非引用上一单元读数） | 本轮实跑 |

## 3. 四条非显然判定（下一单元可直接引为事实）

1. **名称级普查对语义族会「反向缺口」**：`Show` 族文本 2 处 < 判据 8 处，且这 2 处与判据行**无一重合**（一处在 0027 的 `derive(Eq, Debug, Show)`，一处在 `extend StarVerdict with Show::{to_string, output}`）。这解释了为什么 BUG-362 的 11 处盲区只对 `Json::value` 成立——那一族的弃用点恰好长得和弃用件同名。
2. **站点级并集不是出路**：把 `.to_string()`(435) + `inspect(`(39) + 插值 `\{}`(859) 并起来覆盖 11 条判据行是 0 遗漏，但文本面 1333 ⇒ 上限要写到 1322 才不红。棘轮一旦需要这种上限就等价于没有棘轮。
3. **有些判别事实是跨行的**：FFI `Array` 的 3 处全在 `extern "js" fn` 的形参/字段上，而 `: Array[` 有 953 处合法用法。「是否处在 extern 声明里」不是行级正则能表达的，硬要加就需要给守卫引入块作用域扫描——那是另一支工具的活，本单元不做。
4. **入表这一族顺带钉住了 BUG-360**：`star_gate.mbt:302` 与两份 wbtest 的 3 处 `.to_bytes(` 正是 BUG-360 那条「String 内部 UTF-16LE、生产签名侧 UTF-8」验签洞的本体。上限 0 意味着：BUG-360 修完后两面归 0 ⇒ R4 会红并要求把条目整条删掉；半途新写一处不发判据的 `.to_bytes(` ⇒ R3 会红。修到哪一步，门就读到哪一步。

## 4. 资源消耗（自述口径，非计量表读数）

- tokens in ≈ 78 000 / out ≈ 8 600；成本 ≈ 0.26 单位；墙钟 ≈ 620 000 ms（含 `moon check` 与 `moon test` 两轮实跑）
- 工具链：本机 `moon check --target js --json`（shim 环境）；未跑 `moon fmt`/`moon info`（零 `.mbt` 改动，无接口面）
- 探针脚本 6 支（`temp/probe4*.py`、`temp/mk_mut42.py`），全部落 `temp/`，gitignore 面，不进仓

## 5. 任务分配记录

- 指挥官（本机 agent）亲自执行：三向普查、族表条目、`--selftest` 第 10 支、三处文档口径、账本追记、FIST T0r17 生命周期（publish→claim→execute→submit→verify 六格 rc=0）
- 未派子代理：本单元是「一把尺的量程实测」，判据与读数都在同一进程里最可信，拆分反而制造对账成本（金条四：可分配性判断）
- 复核：所有数字由脚本当场产出，未沿用上一单元读数（`temp/chk43.json` 是新产，族分布与 `temp/chk41.json` 逐格相同是**复验结果**而非前提）

## 6. CI 与预存红（如实标注，不粉饰）

- 用户「提交之前一定不能有任何 WARNING」这条在本 PR 仍未达成：489 warnings 中 430 条压在 `Json::value`（等 BUG-361 定案），另 18 条是语义族与 unused 系。按既有裁决「交 CI 当门，PR 里如实标注」处理。
- CI 挂点沿用上单元那两步（`ci.yml` js-ubuntu 臂 selftest + 真判据），族表从 1 条变 2 条**不需要改 CI**：门读的是表，不是数字。
- 预存红三格按既有裁决保持现状、本单元不动（金条四）：`check_py_stdout_encoding --all` / `--selftest`（6 份跟踪脚本缺 stdout 闸，均不在本 PR diff 内，见 BUG-357 后续建议③）、`cleanup_artifacts --check`（仓库残留 DIRTY）。
- 本轮 `moon test` rc 不作判据（本仓已记的不可靠面），判据取计数行：`Total tests: 1302, passed: 1302, failed: 0`，已作为独立一格写进 §2。

## 7. 遗留风险

1. **上限 0 的误红面**：`utf8.encode` 那条代理只在接收者是 `String` 时成立。将来若有人在别的类型上写 `.to_bytes(`（编译器不发判据），R3 会红。处置写在 `audited` 里：收窄正则，不抬上限。
2. **族表覆盖度≠弃用面覆盖度**：0020 现在被表覆盖的是 433/448 条（`Json::value` 430 + `utf8.encode` 3），其余 15 条（`Show` 11、FFI `Array` 3、隐式提升 1）在本工具里**不可测**，只能靠 `error_code` 读数收口——而 BUG-362 已经证明 `error_code` 读数会静默少报。这一格是无解的口径空洞，不是待办；下单元若要用「判据面归零」宣布收口，必须引用 §3.5 说明只适用于语法族。
3. **BUG-361 未定案**：11 处 `Json::value` 本体仍在源码里，缺口上限维持 11。若指挥官选 A 案并要求以文本普查 441 为分母，本守卫的 R3 判定不变（它比的是两面差额），但 §6 九批表的口径要重写。
4. **`0027` 的字面正则陷阱**：`derive(Show)` 普查读 0（真身 `derive(Eq, Debug, Show)`）。已在本单元记入口径，但族表里**没有** 0027 条目——若下单元要加，正则必须用 `derive\([^)]*\bShow\b`。
5. 本单元结论只建立在 js 后端的判据面上。native 后端是否同样漏报仍未复核（本机 native 工具链不可用，沿用 BUG-362 那条未复核声明）。

## 8. 后续建议

1. BUG-361 定案后，把 `Json::value` 的上限随批次下调（每清一处 11→10…），清零后按 R4 整条下线；`utf8.encode` 那条随 BUG-360 同批处理。
2. 若要把 `Show`/FFI `Array`/隐式提升纳入门，需要的不是更宽的正则而是**按文件+按行的白名单式收口**（语义族用「判据行清单」当分母）。建议单开一支 `check_deprecated_site_list.py`，别把族表这把尺撑成两种范式。
3. 建议给守卫补一条 `--dump-distribution` 只读模式（打印 error_code × message 前缀的分布），让「新子族出现」这一格在入表之前就能被读出来——本轮我是手算出来的，成本可以在工具里一次性摊掉。
4. 三族待 owner 裁决的口径已经量化（`Show` 11 条 / FFI 3 条 / 隐式提升 1 条，`FixedArray`、`Executor::run` 两个建议形态全仓 0 处），可以直接进 BUG-361 §7 那张待决表一起看。

## 9. 超额内容（本单元干了哪些不在任务包里的活）

- 把 0027 与 0078 也顺带普查了（任务包只要求 0020 的子族）：得到「`derive(Show)` 字面正则读 0」与「`-> Result[` 437 对判据 3」两条口径，均只写进文档，**未动**族表。
- 用直读 `evaluate()` 的探针（不改族表文件）实测了「硬把语义族入表」的两种 rc，用来验证 docstring 的宣称可复现——任务包没要求这一步。
- 补了 `--selftest` 第 10 支（任务包只要求普查与入表）：理由是本单元自己的 docstring 宣称依赖 `gap < 0` 分支，写而不测不成立。

## 10. 来源

- 判据面：`temp/chk43.json`（本轮 `moon check --target js --json` rc=0）；对照基线 `temp/chk41.json`（R35）
- 普查脚本：`temp/probe43.py`～`temp/probe49.py`、`temp/mk_mut42.py`（temp 面，不进仓）
- 改动文件：`scripts/check_deprecated_text_census.py`（族表 +1 条、docstring 量程段、selftest 第 10 支）、`docs/decisions/2026-10-21-json-value-430-decision.md`（§3.5）、`scripts/README.md`、`memory/bugs.md`（BUG-362 landed）、`memory/2026-10-21.md`（R36）、本报告
- 上游结论：BUG-361（三案量尺与 5 件待决）、BUG-362（判据面静默少报）、BUG-360（验签洞本体）、BUG-344（`error_code` 收口元规则）、BUG-359（逐字命中的适用范围）
