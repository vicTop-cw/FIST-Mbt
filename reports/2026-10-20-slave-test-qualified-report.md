# 2026-10-20 R22 汇报：`slave/fix/test-qualified-imports` —— 清零 0025 test_unqualified_package 803 处

- 分支：`slave/fix/test-qualified-imports`（stacked on `syntax-noise-sweep`(#8) → `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：新根 `T0r3` 承接本单，publish→claim→execute→submit→verify 全部实跑到「已完成」；上一根 `T0` 三叶 + `T0r2` 在册
- 台账：BUG-346（medium，FIXED，轮次 R22）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 1675 | **872** |
| 同判据 errors | 0 | **0** |
| 0025 test_unqualified_package | 803 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 非漂移分歧（43 份文件） | — | **0** |
| bare LF / `Int32` / `~ :` 新增 | — | **0 / 0 / 0** |

43 份 `.mbt`、803 处隐式导入名改为 `@pkg.name` 显式限定；分布 `@server` 210、`@display` 142、`@ops` 123、`@omega` 86、`@evolve` 54、`@router` 53、`@engine` 49、`@diff` 22、`@atgc` 20、`@atgc-old` 19、`@store` 19、`@decompose` 6。

改法不是正则替换：先逐条核对 `loc` 区间切出的文本等于编译器报出的名字（803/803 单行、零错位、零已限定），再按列从右往左就地替换，保证一处改不影响同行另一处的列号。第二轮的 6 处来自 BUG-344 记录的同码同行去重定律 —— 第一轮改完暴露出来，属预期而非脚本 bug。

## 资源消耗

- 工具调用：约 16 次；`moon check --target js --json` 全量 3 次（试点后 1 次、铺满后 2 次）、`moon test` 全量 1 次 + 试点包 1 次、moonfmt 逐文件 2 轮 × 43 份、守卫 1 轮 13 格。
- 本机墙钟：本单约 6 分钟（803 处一改成型，主要是全量 check/test 的编译时间）。
- 返工：2 次。① 判据跑完后 24 份 `.mbti` 已被 `moon check`/`moon test` 重写并混进格式比对输入面，需先 `git restore` 非 `.mbt` 再量格式；② 区间合并把 1 处 `desc~ :` 漂移带进新行，比对时发现后手工还原为 `desc? :`。

## 任务分配记录

- 指挥官亲自做：族选择（在 0025(803) 与 0020(703) 之间按"机械度×存量"取 0025）、试点门槛判定（`atgc-old` 连字符包名先验证）、区间合并策略（只采纳 moonfmt 拆行、拒绝拼写漂移）、终审判据（实跑 check/test/fmt/CRLF 四类）、记忆沉淀。
- 子代理：未派（loc 驱动脚本一次成型，拆行合并只需一轮，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r3` 全生命周期，第五轮连续可证。

## 遗留风险

1. **`.mbti` 污染面**：`moon check`/`moon test` 自身会重写 24 份 `pkg.generated.mbti`（BUG-330 漂移顺带写入）。本轮靠收尾 `git restore -- ':(exclude)*.mbt' '*'` + `check_mbti_sync` 复验兜住；这是工序，不是修复，每轮都要重走。
2. **0020 deprecated(703) 仍是存量主体**：`Json::value` 430 处需要改写取值模式（编译器建议 `if json is Object(obj) { obj.get(key) } else { None }`），非纯机械替换，需按子族分单打。
3. **0079 implicit_impl_as_method(63)**：补 `pub extend T with Eq::{...}` 属接口面动作，会牵 `.mbti`，需单独一轮并逐包 `moon info` 复验。
4. **stacked 合并顺序**：本支依赖 #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 会含祖先改动。
5. **6 处预存 CI 红**与 R21 逐条一致（badge 1108≠1302、test_sync 现状面缺 1302 声明、其 `--selftest` 基准夹具失效、scripts_index 未登记 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 docs/SOP.md:44），均由他单在册，非本单引入；`cleanup_artifacts --check` 报 DIRTY(291) 且 rc=0，属本机残留面，未跑破坏性清理。

## 后续建议

1. 下一单建议 **0020 的 `Json::value` 子族（430）**：先取 3–5 份文件试点量语义影响，再决定批量；这一子族改的是取值路径，比 `not()` 更接近行为面。
2. 顺带把 0002 unused_value(37) 里"测试内故意绑定"的部分改成 `_name`，可作低风险搭车单；`src/engine/*.mbt` 里的真未用值要单独判。
3. BUG-330（`Int`/`Int32`、`? :`/`~ :`）需 owner 定一个方向：只要仓库拼写和本机 moonfmt 不一致，每轮都要付"区间合并 + 手工还原"的税。
4. 建议给 `scripts/` 加一条守卫：判据脚本跑完后检查 `.mbti` 是否仍与 HEAD 一致，防止"顺手提交漂移"。

## 超额内容（本单边界之外做了什么、为什么）

- 为验证 `@pkg-name.`（连字符包名）解析无歧义，先单独跑了一次 `moon check` + `moon test` 试点两个 `atgc` 包；这一步超出"改完统一验"的最低要求，但 803 处一次铺开的风险需要它。
- 未做：未加任何 `warnings = "-..."` 压制；未删死代码（0009/0006/0001 原样）；未动 `.mbti` 拼写面；未跑破坏性 `cleanup_artifacts.py`。

## 来源

- 判据：`temp/chk12.json`（1675/0，改前）、`temp/chk13.json`（878/0，首轮后剩 6 处去重隐藏）、`temp/chk14.json` 与 `temp/chk15.json`（**872/0**，补净与格式合并后复测）、`temp/pt9.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 脚本：`temp/census25.py`（loc 预核 803/803）、`temp/fix25.py`（按 loc 右起替换，带 `seg != name` 守卫）、`temp/apply_fmt25.py`（norm 区间合并）、`temp/fmt25.py`（终态格式比对）。
- 守卫：`check_mbti_sync` / `check_pkg_imports` / `check_tools_sync` / `check_plugin_sync` / `gen_plugins --check` / `gen_plugins --selftest` PASS；其余 6 格见遗留风险 5。
- 台账：`memory/bugs.md` BUG-346 + `### FIXED(2026-10-20 轮次 R22 / BUG-346)`；ledger 330 → 331 条。
- 日志：`memory/2026-10-20.md` R22 小节。
- 既有结论：BUG-344（同码同行只报一次的去重定律，本单二次命中 6 处）、BUG-330（moonfmt 拼写漂移）、BUG-329（本机 bundle-core 合成与 `\\?` ICE）、BUG-32（`fist.py` 入口产物新鲜度守卫，本单再次先 `moon build cmd/cli --target js`）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
