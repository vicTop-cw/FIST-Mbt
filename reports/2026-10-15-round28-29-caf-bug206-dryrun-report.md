# Round 28-29 报告 · BUG-206 Y2038 冷却坑修复 + P2c 标准 3 dry_run 纯计算落地

- 日期：2026-10-15
- 目标：Goal-2 持续【寻虫-修复-验证-推进】循环 —— R28 修 R27 遗留的 Y2038 冷却坑；R29 推进 P2c 验收标准 3 的 dry_run 预览（纯计算部分）
- 状态：**完成**，commit `ed40ada`（R28 BUG-206）+ `54f172c`（R29 dry_run）

## 结果摘要

### R28 · BUG-206：Y2038 后冷却截止静默失效

R27 报告第 45 行已点名这个坑，R28 立即落地成账本条目 + 修复 + 销账闭环：

- **入账**：`BUG-206`（severity=high）—— `ModelQuota::in_cooldown` 里 `cool_secs = iso_to_secs(cooldown_until)` 对 Y2038 后日期因 Int 溢出返回 `-1`，`now_secs < cool_secs` 变成 `2026秒 < -1` 恒 false，冷却机制被完全绕过。
- **修复**（commit `ed40ada`）：`in_cooldown` 加 `if cool_secs <= 0 { return false }` —— fail-open 放行（模型可被再次采用），让下一次 `mark_failure` 用合法时间戳自然重置冷却；比永久锁死可恢复。
- **销账**：`bug_fix` 一次调用同时改抬头为 FIXED + 落 `### FIXED(2026-10-15T11:00:04Z / BUG-206)` 小记。
- **新增契约锁** `cd_4_Y2038 后冷却截止不锁死模型`：三态锁（合法日期冷却 / Y2038 后放行 / 非法字符串放行），153/153 全绿。

### R29 · P2c 验收标准 3：dry_run 预览纯计算部分

`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` 标准 3 原先阻塞在 server 层接线。R29 把**能在 router 包内做完的纯计算部分**先落地（不占用被阻塞的 `model_router_ops.mbt`）：

- 新增 `CafDryRun` struct：`{base, picked, reordered, basis, top_k}`，形状对齐预期产物 `{suggestion, basis:[{model, rate, avg_cost, count}]}`。
- 新增 `ModelRouter::apply_caf`（纯函数）：从 `pick_caf` 拆出的重排步骤，**不重跑 pick、不推进游标**。`pick_caf` 改为 `pick` + `apply_caf` 组合，使 dry_run 的 base/picked 基于**同一次** pick 对照。
- 新增 `ModelRouter::pick_caf_dry_run`：内部 `clone_for_peek` 构造零副作用 probe，在 probe 上跑一次 pick + apply_caf。**调用方零副作用**（原 router 的 free_idx/paid_idx/current_tier/last_pick/config.free_models[].window_start 均不被改动）。
- 新增 `clone_pools`：**深拷贝** pool 数组。踩坑记录——初版写 `config.free_models.map(fn(m){m})` 实测**仍污染**原 config（MoonBit 对恒等闭包做 copy elision，返回的仍是原 object 引用）；改成显式走 `ModelQuota::new` 重建每个 quota 才拿到独立值。白盒锁 `caf_dry_1` 钉住了这个坑。
- **3 条白盒锁**：`caf_dry_1`（零副作用）/ `caf_dry_2`（对照语义）/ `caf_dry_3`（关闭 CAF 零回归），router 156/156 全绿。

## 资源消耗

| 项 | R28 | R29 |
|---|---|---|
| 涉及文件 | 2（`model_router.mbt` + `model_router_wbtest.mbt`） | 3（`model_router_caf.mbt` + `model_router_caf_wbtest.mbt` + `pkg.generated.mbti`） |
| 新增行数 | 33 | 214 |
| 测试基线 | src/router 152→**153** | src/router 153→**156** |
| 提交门禁 | `moon fmt` + `moon test --target js src/router` 全绿 | 同左 + `moon info` 同步 `.mbti`（首次 moon info 卡文件锁失败，重跑成功） |
| 全仓 `moon test --target js` | 仍不可跑：并发 agent WIP 在 `src/constraint`/`src/core`/`src/symbolic` 有 parse error（非本轮引入） | 同左 |

## 任务分配记录

| 步骤 | 执行者 | 结果 |
|---|---|---|
| BUG-206 入账 + 修复 + 契约锁 cd_4 | 主 agent | ✅ commit `ed40ada` |
| BUG-206 销账 | 主 agent | ✅ `bug_fix`（heading_changed=1） |
| pick_caf_dry_run / apply_caf / CafDryRun / clone_for_peek / clone_pools | 主 agent | ✅ commit `54f172c` |
| caf_dry_1~3 白盒锁 | 主 agent | ✅ 156/156 |
| 两份 docs 状态同步 | 主 agent | ✅ 验收状态表 + wiring 设计头部 |

## 遗留风险

1. **P2c §2.3 仍在阻塞**：回写（`executor_run` 后 `caf_memory.push`）+ status 展示（`caf_memory.count/enabled`）依赖 `src/server/model_router_ops.mbt`，被并发 agent WIP 占用。dry_run 纯计算已就绪，接线时只需把 `caf_memory` 从进程内存传入 `pick_caf_dry_run` 再序列化 `CafDryRun`，无额外 router 层改动。
2. **全仓回归仍未跑**：并发 agent WIP 未提交的 parse error 挡住 `moon test --target js` 全仓。router 包 156/156 是本轮可靠基线。
3. **BUG-206 fail-open 的语义取舍**：`cool_secs <= 0` 时放行（不锁死模型）是"宁可多试一次"的保守选择；若生产上担心 Y2038 冷却被绕过，可在 `mark_failure` 写入前 clamp 冷却截止到 Y2038 内，从源头杜绝坏值进入。当前未做，因 `cooldown_until` 由 server 层 `now + cooldown_secs` 计算，正常不可能超 Y2038。
4. **文档落地位置偏差**：wiring 设计 §2.4 原写测试落在 `src/router/router_caf_wbtest.mbt`，实际落在 `model_router_caf_wbtest.mbt`（避开并发 agent 的 `router_caf*` WIP 域），已在设计文档头部注明。

## 后续建议

1. 并发 agent WIP 收口后：实施 §2.3 回写 + status（`pick_caf_dry_run` 已就绪），随后跑全仓 `moon test --target js` 确认零回归。
2. P2d 冷启动启发式 `caf_soft_reorder_with_preference` 与 §2.2 一起在 §2.3 收口后统一接线。
3. 可选加固：`mark_failure` 写入前 clamp 冷却截止到 Y2038 内（源头上杜绝坏值），消除 BUG-206 fail-open 的语义歧义。
4. 下次遇到 `Array[T].map(fn(x){x})` 意图深拷贝时，先想 MoonBit 的 copy elision——显式构造才是可靠路径。

## 超额内容

- 无（R28/R29 严格在 src/router + docs + reports + memory 允许作用域内）
