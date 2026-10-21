# 2026-10-21 R27 汇报：`slave/fix/deprecated-derive-show` —— 0027 derive(Show) 弃用面清到承重边界（5→1）

- 分支：`slave/fix/deprecated-derive-show`（stacked on `implicit-impl-as-method`(#13) → `unused-value-locals`(#11) → `reserved-keyword-and-priv`(#12) → … → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0r8` 走完整生命周期 publish→claim→execute→submit→verify 至「已完成」（deliverable 落库），连续第十轮自我迭代可证
- 台账：BUG-351（low，FIXED，轮次 R27）—— 本分支链上第三份动 `.mbti` 接口面的单（收缩→扩张→收缩）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 588 | **581** |
| 同判据 errors | 0 | **0** |
| `error_code` 0027 deprecated_syntax | 5 | **1**（残留 = `StarVerdict`，owner 决策） |
| `error_code` 0020 deprecated | 527 | **524**（Show 派生副产品 3 条） |
| `error_code` 0079 / 0071 / 0029 | 0 / 0 / 0 | **0 / 0 / 0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| `moon build cmd/cli --target js` | rc=0 | **rc=0** |
| moonfmt 非漂移分歧（4 份 .mbt） | — | **0** |
| `check_mbti_sync` | PASS（654 条） | **PASS（654 条）** |

改动 5 份文件（4 份 `.mbt` + 1 份 `pkg.generated.mbti`），+10/−35 行：5 处闭合行剥 `Show`、5 块 `pub extend T with Show::{to_string, output}` 撤销、接口镜像收缩 10 行方法声明 + 5 处闭合行去 Show。`src/router/star_gate.mbt` 与 `StarVerdict` 接口面原样保留。

## 资源消耗

- 工具调用：约 22 次；`moon check` 全量 3 次（基线 588 / 过度剥离 408+20err / 终态 581）、包级试点 1 次、`moon test` 全量 1 次、`moon build cmd/cli` 1 次、moonfmt 逐文件 1 轮 × 4 份、守卫 1 轮、批量工具 3 版（fix27 / fix27all / fix27b / **fix27c**）、FIST 生命周期 6 次调用。
- 本机墙钟：本单约 12 分钟（含一次全树返工）。
- 返工：2 次 —— ① 首版批量工具按 `startswith("derive(")` 找 derive 行，实发 0 命中（列表在闭合行 `} derive(Show, Eq, Debug)` 上）；② 无差别改 mbti 闭合行把 `StarVerdict` 一起冲掉，靠 `assert c == 5`（实发 6）拦下，`git restore -- src/router/` 后按块归属重写终版。两次都是"边判边写"留下的半改态促成，终版改为全部断言通过才落盘。

## 任务分配记录

- 指挥官亲自做：0027 与 Show 依赖链的边界判断（哪些类型零消费者、`StarVerdict` 为何是承重面）、过度剥离的取证（20 条 4015/4018）、mbti 块归属规则、终审判据（check/test/build/fmt/守卫实跑）、记忆沉淀。
- 子代理：未派（5 处改动 loc 驱动一次成型，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r8` 全生命周期，连续第十轮。

## 遗留风险

1. **`StarVerdict` 的 1 条 0027 是 owner 决策，不是技术遗留**：Show 被生产 `to_json` 与 19 处白盒 `inspect` 依赖。两条出路各有代价——手写 `impl Show`（弃用面继续存在）vs 迁到 `Debug`/`to_repr`（动生产序列化与测试断言）。本单按"不动承重面"收敛。
2. **接口面收缩仍无生成器背书**（BUG-330 未解）：本单镜像靠手写 + `moon check` 复验（0027 命中 4→0 即背书）。`moon info` 在本机 0.10.16 仍不可用（242 行残留漂移）。
3. **`.mbti` 闭合行块归属是本轮新识别的坑**：闭合行不带类型名，跨类型批量改必须有归属跟踪；工序若漏掉，判据一跑就冲掉手工镜像（BUG-346 定律第六次确认）。
4. **stacked 合并顺序**：本支依赖 #13 → #11 → #10 → #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
5. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入；`cleanup_artifacts --check` 仍 DIRTY，属本机取证件累积，未跑破坏性清理。

## 后续建议

1. 下一单建议 **0078 result_error_return**(13)：真签名变更（`Result[T, E]` → `T raise E`），要逐站看调用面与 mbti 镜像，不宜机械铺开；本单"闭合行块归属 + 断言后落盘"的工具形态可直接复用。
2. **`StarVerdict` 单独立项**（0027 收尾 5→0）：先量测 `to_json` 的 verdict 字段有没有下游消费者依赖其字符串形态，再决定手写 impl 还是迁 `Debug`。
3. **接口面工序写进 `docs/SOP.md`**：三轮下来（BUG-349/350/351）每轮踩不同侧面，"镜像 + keep 备份 + restore 复验 + 闭合行块归属"应当是文档化的固定动作。
4. 0020 语义档 524 的入口还是那个决策：`Json::value` 主体要不要引入包内 `priv fn` 辅助。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了"6 个类型全剥"的过度剥离取证（`temp/chk27.json` 408 warnings / 20 errors），把"`StarVerdict` 为什么不能动"从 grep 猜测变成编译器实证，后续同类单可直接引用。
- 加做了批量工具的第三次重构（断言后落盘 + 块归属跟踪），代价是 1 轮返工，产出是可复用到 0078 的安全改批形态。
- 未做：未加 `warnings = "-..."` 压制、未删死码（0001/0006/0007/0009）、未动 0020 语义档、未动 `Result[T,E]`→`raise` 签名、未跑破坏性 `cleanup_artifacts.py`、未替 owner 决定 `StarVerdict` 走哪条路。

## 来源

- 判据：`temp/chk26.json`（588/0，改前，0027=5、0020=527）、`temp/chk27.json`（408/**20 err**，过度剥离取证）、`temp/chk28.json`（**581/0**，终态，0027=1、0020=524）、`temp/pilot27.json`（单点试点）、`temp/pt14.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 站点面：`git grep "derive(.*Show"` 于 HEAD 命中 6 处（ofm_chat 2 + ofm_failure/ofm_models/ofm_response/star_gate 各 1），对照 5 条告警 ⇒ 建立"0027 按 (文件, 码) 报"的读数。
- 镜像备份：`temp/keep27/src/router/pkg.generated.mbti`（终态与之 diff 为空）。
- 守卫：`check_mbti_sync` PASS（654 条）、`check_pkg_imports`、`gen_plugins --check`、`gen_plugins --selftest`、`check_plugin_sync`。
- 台账：`memory/bugs.md` BUG-351 + `### FIXED(2026-10-21 轮次 R27 / BUG-351)`；`memory/2026-10-21.md` R27 小节。
- 改法脚本：`temp/fix27c.py`（终版：剥 Show + 撤 extend + 镜像收缩，块归属跟踪、断言后落盘），前代 `temp/fix27.py` / `fix27all.py` / `fix27b.py`；驱动 `temp/t8_drive.py`。
- 既有结论：BUG-344（复跑命中才算收口）、BUG-346/348/349/350（check/test 重写 mbti 的工序，本单第六次确认）、BUG-330（拼写漂移，接口面无法生成器背书）、BUG-32/329（fist.py 驱动次序）。
- 仓库规范：`AGENTS.md` 金条四/五/八（含 `moon info` 后须审 `.mbti` diff 的要求）、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
