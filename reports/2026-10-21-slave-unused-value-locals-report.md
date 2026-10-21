# 2026-10-21 R24 汇报：`slave/fix/unused-value-locals` —— 0002 非参数绑定子族清零（20 条）

- 分支：`slave/fix/unused-value-locals`（stacked on `deprecated-api-renames`(#10) → `test-qualified-imports`(#9) → `syntax-noise-sweep`(#8) → `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0`/`T0r2`/`T0r3`/`T0r4` 均已完成；本单挂新根 `T0r5` 走完整生命周期（publish→claim→execute→submit→verify）
- 台账：BUG-348（low，FIXED，轮次 R24）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 696 | **676** |
| 同判据 errors | 0 | **0** |
| `error_code` 0002（unused_value） | 37 | **17** |
| 非参数绑定档命中（let / for / match 臂 / lambda） | 20 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| moonfmt 非漂移分歧（10 份文件） | — | **0** |
| `.mbti` 接口变更 | — | **0**（check_mbti_sync PASS） |

改动 10 份 `.mbt`（+20/−20 行）：`let` 绑定 10 处、`for` 绑定 6 处、`match` 臂 2 处（`Ok(res)`→`Ok(_res)`）、`lambda` 参数 1 处（`fn(_k, v)`）、`src/server/server.mbt` 手修 3 处（`let _score`、2 处 `fn(_args : Json)`）。全部只加 `_` 前缀，无删除、无重排、无签名变化。

## 资源消耗

- 工具调用：约 18 次；`moon check --target js` 全量 4 次（试点 691/0、误伤态 374 错误、复跑 678/0、终态 676/0）、`moon test` 全量 1 次、moonfmt 逐文件 2 轮 × 10 份、守卫 1 轮 × 13 例、FIST 生命周期 5 次调用。
- 本机墙钟：本单约 13 分钟。
- 返工：3 次，全部是改法自身的错，不是判据不达标 —— ① 包级 `let laya_client_budget_ms` 加前缀打断白盒测试（回滚 + 入账）；② 签名整串替换误伤 134 个处理器（374 条错误）；③ 反向还原抹掉 owner 已写的 8 处 `_args`（`git restore --source=HEAD` 后按行号点改）。

## 任务分配记录

- 指挥官亲自做：0002 分档（参数位 vs 非参数绑定）、`~label` 契约风险的判断、三处返工的定位与回滚、终审判据（实跑 check/test/fmt/守卫）、记忆沉淀。
- 子代理：未派（20 处改写由 loc 驱动脚本一次成型 + 3 处手修，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py`（本机构建产物）驱动 `T0r5` 全生命周期，连续第七轮。

## 遗留风险

1. **0002 仍有 17 条**，全在参数位与 1 处包级 `let`：形参名同时是 `~label:` 契约，改 `_` 或删除都可能打断调用点与 `.mbti`，必须与 0004 missing_priv(11) 一起按"接口面"单处理。
2. **白盒测试同包可见性**（坑②）是普适风险：任何"本文件读不到就判死"的清理（0001/0006/0009/0029）都可能打断 `_wbtest.mbt`/`_test.mbt`，后续轮次要保留这条前置检查。
3. **stacked 合并顺序**：本支依赖 #10 → #9 → #8 → #7 → #6 → #5 → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 含祖先改动。
4. **6 处预存 CI 红**逐项与改前一致（badge 1108、test_sync 现状面缺 1302 声明、其 selftest 基准夹具、scripts_index 的 `run_check_t0r21.py`、doc_surface 的 USAGE 0.3.8、entry_paths 的 SOP.md:44），非本单引入。
5. **`scripts/cleanup_artifacts.py --check` 仍报 DIRTY(319)**：本机 `temp/` 取证件累积，属仓库既有口径差异，本单未跑破坏性清理。

## 后续建议

1. 下一单建议 **0079 implicit_impl_as_method**(63) 或 **0035 reserved_keyword**(13)：前者编译器已给确切 `pub extend … ::{to_repr}` 声明文本，后者只需把 `local`/`namespace` 形参改名（label 感知）。
2. 或按"接口面"合并单：0002 参数位 17 条 + 0004 missing_priv(11) 一起，判据是 `moon info` 后 `.mbti` 的逐条 diff 复审。
3. `Json::value`(452) 试点仍挂着：建议 `src/server/bugreport*.mbt` 与 `src/engine/engine_circuit.mbt` 先做 3–5 份，量测是否需要 `get_or` 辅助函数。
4. BUG-330（`Int`/`Int32`、`? :`/`~ :`）仍待 owner 决策；本轮因其未触发（无拆行）而验证成本归零，说明"少动行宽"的档位天然更稳。

## 超额内容（本单边界之外做了什么、为什么）

- 把 binder 分类白名单 + 标识符边界自检固化进 `temp/fix02.py`（`fn` 声明、label、可选 `?`、`~`、`self` 一律跳过），下一轮参数位单可直接复用同一分类器。
- 未做：未加任何 `warnings = "-..."` 压制、未删任何"看起来没用"的形参或包级 `let`、未动 `.mbti` 拼写面、未跑破坏性 `cleanup_artifacts.py`、未动 0020 语义档。

## 来源

- 判据：`temp/chk20.json`（696/0，改前）、`temp/chk21.json`（691/0，试点）、`temp/chk22.json`（374 错误，误伤态取证）、`temp/chk23.json`（678/0）、`temp/chk24.json`（**676/0**，终态，非参数绑定命中 0）、`temp/pt13.log`（`Total tests: 1302, passed: 1302, failed: 0`）。
- 守卫：`check_pkg_imports` / `check_mbti_sync` / `gen_plugins --check` / `gen_plugins --selftest` / `check_plugin_sync` PASS；`temp/run_guards11.py` 全 13 例输出。
- 台账：`memory/bugs.md` BUG-348 + `### FIXED(2026-10-21 轮次 R24 / BUG-348)`；`memory/2026-10-21.md` R24 小节。
- 改法脚本：`temp/fix02.py`（binder 白名单 + 边界自检）、`temp/apply_fmt25.py`（norm 区间合并，本轮未触发）、`temp/t5_drive.py`（FIST 生命周期）。
- 既有结论：BUG-344（同行同码去重量法）、BUG-346（check/test 重写 mbti 的工序）、BUG-347（0020 机械改名档边界）、BUG-329/330（`\\?` ICE 与拼写漂移）、BUG-32（fist.py 入口产物新鲜度守卫）。
- 仓库规范：`AGENTS.md` 金条四/五/八、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
