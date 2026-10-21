# 2026-10-20 R20 汇报：`slave/fix/deprecated-not-operator` —— 0020 deprecated 的 `not(x)` 子族清零

- 分支：`slave/fix/deprecated-not-operator`（stacked on `slave/fix/core-package-imports` → `slave/fix/unused-package-deps` → `slave/fix/moonc-0.10.16-result-api`）
- 父任务：FIST `T0`（清零 moon check 告警逐族）｜子任务：`T0.3`
- 台账：BUG-344（medium，FIXED，轮次 R20）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 1895 | **1694** |
| 同判据 errors | 0 | **0** |
| 0020 deprecated 族 | 904 | 703 |
| 子形状 `Use !expr instead` | 201（清单）/ **203**（真值） | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 对 `!` 相关行的分歧 | — | **0** |
| 62 份文件 bare LF（CRLF 面完整性） | — | **0** |

改动：62 份 `.mbt` 里 203 处 `not(x)` → `!x`；7 处保留必要括号（`!(tight < loose)`、`!(phi2 > phi1)`、4 处 `is` 模式、1 处跨行 `||` 串）；另按格式化器要求合并 5 处因表达式变短而应并行的折行。零接口变更、零行为变更。

## 资源消耗

- 工具调用：约 22 次（其中 `moon check --target js --json` 3 次全量、`moon test --target js -j 1` 全量 1 次、moonfmt 逐文件实测 3 轮 × 62 份）。
- 本机墙钟：本单约 20 分钟（测量占大头：`moon check` 单次 60–90s、`moon test` 单次 100s）。
- 返工：2 次（首版保守加括号 → 剥括号规则改为按深度 0 判定；折行合并 + 缩进对齐）。
- 未消耗：无新增依赖、无网络请求、无 CI 额度（本机自测代替）。

## 任务分配记录

- 指挥官（本机主会话）亲自做：族选择与分流判断（在 0020 三个子形状与 0025 之间比过 ROI 与风险）、改写规则设计、终审判据（实跑 `moon check` + `moon test` + moonfmt 逐行比对）、记忆沉淀。
- 子代理：本单未派（机械改写用脚本 + 编译器判据自证，派子代理反而多一层取证成本）。
- FIST 自我迭代：用本机构建的 `fist-mbt` 命令驱动 `T0.3` 走 `claim → execute → submit → verify` 全链，`T0` 三叶（T0.1/T0.2/T0.3）至此全部已完成。

## 遗留风险

1. **同行同码去重**：moonc 0.10.16 对同一行内同一 `error_code` 只出一条告警。任何以 `--json` 清单为工单的族，清单数 ≠ 真实命中数；本单靠 `grep '\bnot('` 复核才暴露 2 处。后续族必须保留"文本面复核"这一步。
2. **native 面本机量不了**：`moon check --target native` 缺 core native bundle（BUG-329 同族机器级缺口），无法读 native 侧 warning 数。`not()` 与 `!` 在两后端同语义，风险限于 js 侧格式化面；交 CI native job 当门。
3. **格式化器版本面**：本机 moonfmt 是 0.10.16，它对 `Int`/`Int32`、`x? :`/`x~ :` 的拼写要求与仓库存量系统性不一致（BUG-330，未解）。本单只保证"我改的行"与新版 moonfmt 无分歧，未做全仓 `moon fmt`（那属独立决策）。
4. **6 处预存 CI 红**逐项与改前一致（`check_badge` README 徽章 1108、`check_test_sync` 现状面无 1302 声明、其 `--selftest` 基准夹具失效、`check_scripts_index` 未登记 `run_check_t0r21.py`、`check_doc_surface` USAGE 自述 0.3.8≠moon.mod 0.3.9、`check_entry_paths` docs/SOP.md:44 引用退役入口 `cmd/main`）。非本单引入，未顺手扩大改动面。
5. **stacked 分支合并顺序**：本支依赖 `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`（BUG-328 适配，master 树当前不可编译）。MR base 若默认 master，diff 会含祖先改动，需按顺序合。

## 后续建议

1. 0020 剩余 703 条里最大子形状是 `Json::value`（430 条，建议语 `if json is Object(obj) { obj.get(key) } else { None }`）—— 需要逐包 `priv` 辅助函数，工序量级高于本单，建议单独开单（我可以先做族谱分桶 + 一版 helper 设计再动手）。
2. 小族清扫按低风险排序：0008 redundant_modifier(12) + 0021 missing_pattern_arguments(6) + 0067 unused_async(1) + 0013 unresolved_type_variable(1) 可并成一单（纯语法、零语义）。
3. 0025 `test_unqualified_package`(803) 是本仓最大的一块"可清零"资产，但它是逐点加 `@pkg.` 限定（42 份测试文件），建议先做 3–5 份文件的试点量测，确认黑盒测试语义与快照不受影响后再批量。
4. BUG-330（Int/Int32）需 owner 决策：要么一次全仓 `moon fmt` 落新拼写，要么把 CI 的 moon 版本钉到与存量一致。这条不解决，"提交前零 warning + 零 fmt 分歧"在本机永远是两套真源。

## 超额内容（本单边界之外做了什么、为什么）

- 为族谱进度做了分桶测量（0020 三个子形状 + 0025 + 17 族全量计数），因为分流决策必须先知道哪一族 ROI 最高；测量只读，不改代码。
- 顺带把 moonfmt 逐行比对法固化成 `temp/fmtverify2.py`（drift 剔除 + 只看主题相关行），下一族可直接复用。
- 未做：未删/未改任何 API、未压制告警（`warnings = "-..."` 一类 hack 一个都没加）、未跑 `cleanup_artifacts.py` 的破坏性清理、未动 `.mbti`（统一 `git restore`）。

## 来源

- 编译器判据：`temp/chk9.json`（改写后 1696/0，暴露 2 处清单外残余）、`temp/chk10.json`、`temp/chk11.json`（最终 **1694 warnings / 0 errors**）；`temp/pt7.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 守卫读数：`temp/run_guards7.py` 输出（13 项，6 红 1 DIRTY 与改前逐项一致）。
- 台账：`memory/bugs.md` BUG-344 + `### FIXED(2026-10-20 轮次 R20 / BUG-344)`；ledger 328 → 329 条。
- 日志：`memory/2026-10-20.md` R20 小节。
- 工具链既有结论：BUG-329（bundle-core 合成、`moon fmt` 的 `\\?\` ICE 同族第二道与 `moonfmt.exe -o` 绕法）、BUG-330（Int/Int32 与可选参数糖拼写漂移）、BUG-342/343（依赖面两族、native 面缺口）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，本单逐路径显式 staging）。
