# 2026-10-21 · R31 · slave/fix/json-bool-string-accessors（PR #18）

## 结果摘要
- 目标：清零 0020 deprecated 的 Json 布尔/字符串访问器子族——`Json::as_bool` 15 处 + `Json::as_string` 7 处，共 22 处，10 份 `.mbt`。
- 判据面：`moon check --target js` **523 → 501 warnings / 0 errors**；`error_code` 20 命中 482 → 460（这两族 22 → 0），其余族 1:9 / 2:11 / 6:12 / 7:2 / 9:3 / 27:1 / 78:3 逐格不变。
- 测试面：`moon test` → `Total tests: 1302, passed: 1302, failed: 0`（改前后各实跑一次）。
- 构建面：`moon build cmd/cli --target js` rc=0。
- 接口面：零变化，`.mbti` 未改（`check_mbti_sync` PASS，654 条不变）。
- 提交：`8a68ec7`(上一单元) 之上单提交，分支 `slave/fix/json-bool-string-accessors` 推 gitcode，MR 由指挥官开（base `master`）。

## 资源消耗
- 主代理轮次：1 个目标轮内完成（拉取基线 → 族分类 → 等价性取证 → 批量改写 → 格式化重折 → 全量验证 → 文档与投影）。
- 实跑次数：`moon check --target js --json` 3 次（chk34 基线 / chk35 改后 / chk36 重折后），`moon test` 2 次，`moon build` 1 次，`moonfmt` 只读 20 次（10 文件 × HEAD/现版）。
- FIST 记账：execute 记录 tokens-in 96,000 / tokens-out 12,500 / cost 0.31 / duration 420,000 ms（模型 qoder-agent）。

## 任务分配记录
- T0r12（根任务，第 14 次连续完整生命周期）：publish → claim → execute → submit → verify 全通过，状态 已完成。
- 子代理：无。本单元属"轻-中"改写 + 强验证，判据取证与终态判定留主代理（金条八要求实跑，不依赖自述）。
- 批量工具：`temp/fix31.py`（22 处，逐块断言唯一命中 + 新标识符冲突断言 + dry-run 先行）、`temp/fix31b.py`（moonfmt 要求的 7 处重折）、`temp/fmt30.py`（D0/D1 同尺分歧度量）、`temp/t12_drive.py`（FIST 生命周期）。

## 遗留风险
1. **`Json::value` 一族 430 条未动**：占全部剩余 warning 的 82%，是"零 WARNING"目标的主障碍。铺开方式二选一（包内私有辅助 vs 逐点模式匹配），会动 53 份文件、20+ 包的调用面，属架构口味 → 按金条四留 owner 决策，本轮不自决铺开。
2. **`check_test_sync` / `check_badge` 预存红**：README 徽章 1108/1108、README 正文 1112、AGENTS/deliverable 1058、agent-map 1058，实测 1302。本轮未改这 5 份文档（改它们等于替现状面做数字口径决策），按"交 CI 当门，PR 里如实标注"处理。
3. 0020 其余零散族：`reinterpret_as_int64` 11、Show/Debug 8+3、`utf8.encode` 3、JS FFI `Array`→`FixedArray` 3、`Int::unsafe_to_char` 1、隐式提升 1 —— 每处需按语义判定，不可机械改名。
4. `as_bool().unwrap_or(false) ⇒ v is Json::True` 与 `as_string().unwrap_or("") ⇒ if v is String(s) {s} else {""}` 是真值表折叠，形状变了；已由账本记档 + 1302 测试实跑钉住，但若未来 `Json` 表示再变（如 `Boolean(Bool)` 回归），这两处的折叠前提需重查。
5. 本机工具链限制不变：`moon fmt`/`moon info`/`moonc` 仍 ICE（`Sys_error("\\?: Invalid argument")`），格式化判定只能走只读 `moonfmt.exe`。

## 后续建议
1. 下一单元优先做 `Json::value` 430 的**决策稿**：给出包内私有辅助的形状（含命名与放置约定）与逐点匹配的 diff 体量对比，请指挥官二选一后铺开——这是通往"零 WARNING"的唯一大件。
2. 现状面文档测试总数一次性同步（1108/1112/1058 → 实测值），并复核 `check_test_sync` 的豁免表条目有效性；这能一次收掉两条预存 CI 红。
3. 剩余 0020 零散族（`reinterpret_as_int64` 11 / Show→Debug 8+3 / `utf8.encode` 3 / FFI `FixedArray` 3）按"一处一判"节奏继续。
4. owner 清单继续挂：BUG-354 的 10 条 0002、0078 残 3、0027 残 1（`StarVerdict`）、死码族 0001/0006/0007/0009、BUG-330 的 `Int`/`Int32` 拼写漂移。

## 超额内容
- 顺带把 0020 剩余族做了完整分族计数表（430/15/11/8/7/3/3/1/1 + 其余族），可直接当下一单元的排期输入。
- 把"新增格式分歧必须为 0"的 D0/D1 同尺度量脚本复用到本单元（`temp/fmt30.py` 无需改动即适用 HEAD 变化）。

## 来源
- `C:/Users/Administrator/.moon/lib/core/json/json.mbt:23-48`（`as_bool` / `as_string` 弃用属性与实现体 ⇒ 等价性定死）
- 仓内既有惯用法对照：`src/hat/hat_config.mbt:194-215`、`src/router/router_caf_dryrun_json_wbtest.mbt:20-40`、`src/router/router_caf_persist.mbt:106-107`
- 判据面：`temp/chk34.json`（523 基线）、`temp/chk35.json`（501 改后）、`temp/chk36.json`（501 重折后）
- 测试/构建面：`temp/pt18.log`、`temp/pt18b.log`（1302/1302/0）、`temp/build18.log`（rc=0）
- 守卫面：`temp/g18_check_mbti_sync.log`、`temp/g18_check_pkg_imports.log`、`temp/g18_check_plugin_sync.log`、`temp/g18_gp_check.log`、`temp/g18_gp_self.log`、`temp/g18_tools_sync.log`、`temp/g18_test_sync2.log`（唯一红，见遗留风险 2）
- FIST：`temp/fist-selfiter.db` 任务 T0r12
