---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_b7f88450b49f11f193fb525400393706
    ReservedCode1: qeKbQsuuWS1wvfZw9+kz2b5r7VALzAKL/JFxJW4HaqJZ+Vv2JFFFEDcv2flphQhUeucWDEukzTNXWA0xOyAQL0UCCQqAu+r4xJEjifrwsiKsGw7s1WrWr4H7gsbZMNDRmKwxfdmuepwsCsr0l+urYyyWykGH51rCWtgwdU/hn/at65kRQ/Qv/MKaSps=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_b7f88450b49f11f193fb525400393706
    ReservedCode2: qeKbQsuuWS1wvfZw9+kz2b5r7VALzAKL/JFxJW4HaqJZ+Vv2JFFFEDcv2flphQhUeucWDEukzTNXWA0xOyAQL0UCCQqAu+r4xJEjifrwsiKsGw7s1WrWr4H7gsbZMNDRmKwxfdmuepwsCsr0l+urYyyWykGH51rCWtgwdU/hn/at65kRQ/Qv/MKaSps=
---

# FIST-Mbt Watchdog 流水线状态机化 —— 空转根因修复报告

- 日期：2026-09-20
- 范围：`src/ops/ops_pipeline.mbt`（新增）、`src/ops/ops_pipeline_test.mbt`（新增）、`src/engine/engine.mbt`、`src/server/server.mbt`、`pipeline_tick_cron.py`（新增）
- 输入：`C:\Users\victo\watchdog_meta_prompt.md`（currentState.txt 状态机版元提示词）
- 状态：已完成，123/123 测试通过，端到端沙箱六场景验证通过

---

## 一、现象与根因

现象：Pentad 的 `cron-auto` 命名空间连续多轮只产出任务、无成果：任务链 T0r2~T0r16 全部停在「待领取」，提示词每 45 分钟持续新增，项目实际推进为零。

三层根因，缺一不可：

| 层 | 位置 | 问题 |
|---|---|---|
| 推进判据 | `watchdog_tick_cron.py` | 客户端仅比较「Gen_Prompts 最新提示词是否比 `last_consumed` 新」就调用 watchdog_tick 发布下一轮，**不检查命名空间内是否有在途任务**，导致任务无限堆积 |
| 服务端能力 | `ops_watchdog.mbt` | `watchdog_tick` 只在 `pending_advance`（有待续轮根任务）或 `cold_start` 时才发布任务；**不存在「读取 currentState.txt → 按状态机消费 Gen_Prompts 提示词」的推进路径**，状态机完全依赖客户端实现 |
| 状态收口 | 元提示词约定 | 「报告先行」未落到代码层校验，出现「Closed 但无报告」的断档后无人可续 |

## 二、设计：把元提示词状态机下沉为服务端工具

新增 `pipeline_tick(project_dir, now, namespace, timeout_sec, phase, prompt_name)`，把 `watchdog_meta_prompt.md` 的 A/B/C/0 四分支在服务端实现，客户端不再自行判断是否推进。

`currentState.txt` 状态 → 动作映射（实测输出）：

| state_in | action | state_out | 行为 |
|---|---|---|---|
| absent / Creating | generate | Creating | 允许生成新提示词（外部 LLM 落盘后置 Pending） |
| Pending | execute | Running | 发布/续轮根任务，写幂等标记 `[prompt:<文件名>]` |
| Pending | wait | Pending | **在途任务未完成或无可续轮根任务 → 不发布、不堆积** |
| Pending | write_report | Pending | 上一轮已非活跃但报告缺失，先补报告 |
| Running | wait | Running | 任务未超时，本轮不动 |
| Running | closed | Closed | 报告已落盘，状态收口 |
| Running | write_report | Running | 超时且无报告，要求补报告（绝不写「Closed 无报告」） |
| Closed | generate | Creating | 上一轮报告齐备，推进下一轮 |
| Closed | write_report | Closed | 报告缺失，阻塞推进（报告先行） |
| invalid | safe_exit | invalid | 状态不可识别，不改任何状态 |

关键约束：

- **报告先行**：写 `Closed` 前校验 `Reports/<提示词同名>.md`（兼容 `reports/`）已落盘，缺失即拒绝续轮。
- **namespace 隔离**：仅接受显式 namespace（如 `cron-auto`），`default` 直接拒绝，人工指挥流程零影响。
- **不写脏数据**：任何失败路径只上报、不回滚提示词、不覆盖已有文件；超时心跳由 `heal_stale_tasks_from_store` 跨进程回滚并上报 `healed`。
- **幂等**：同一提示词重复 tick 不重复发布（幂等标记）。

附带修复：`engine.mbt` 新增 `first_free_root_id()`，冷启动首个根任务 id 由错误的 `T0r2` 修正为 `T0`（原 `next_round_id()` 永不返回 T0）。

## 三、验证

单元测试：`moon test` → **Total tests: 123, passed: 123, failed: 0**（新增 `ops_pipeline_test.mbt` 16 个用例，覆盖 generate/execute/wait/幂等/超时/heal/报告先行/Closed 续轮/非法状态/default 拒绝/堆积防护）。

端到端沙箱（真实 MCP 协议 + 独立 ns `cron-sandbox`，脚本 `temp/e2e_pipeline_check.py`）：

| 场景 | 输入 | 实测 action | 结论 |
|---|---|---|---|
| S1 冷启动 | 无 currentState.txt | generate | 进入分支 A，状态置 Creating |
| S2 提示词就绪 | Pending + 提示词 | execute（T0r18） | 根任务发布并在途，状态 Running |
| S3 **空转回归** | 在途未完成 + 新提示词 | **wait** | 任务总数保持 1，**不再堆积** |
| S4 报告缺失 | Closed 但无报告 | write_report | 报告先行生效，拒绝续轮 |
| S5 补齐报告 | Closed + 同名报告 | generate | 正常推进下一轮 |
| S6 非法状态 | `Garbage` | safe_exit | 状态未被修改 |

## 四、接入方式

新增驱动脚本 `pipeline_tick_cron.py`（不替换旧脚本，可回退）：

```
python pipeline_tick_cron.py               # pentad + tnr 各 tick 一次
python pipeline_tick_cron.py --project pentad
```

每次唤醒只调用 `pipeline_tick` 并按其返回分支行动：

- `generate` → 外部 LLM 生成 `Gen_Prompts/yyyyMMdd.HH.mm.ss.md`，落盘后置 `Pending`，再由 `pipeline_tick` 发布任务；
- `execute` → 任务已发布，交由 `execute_cron.py`（codearts 执行侧）领取消化；
- `wait` → 本轮无动作（在途任务未完成）；
- `write_report` → 补写 `Reports/<同名>.md`；
- `safe_exit` → 人工确认 `currentState.txt`。

切换步骤（需人工执行，未自动变更）：将 schtasks / AtomCode 中指向 `watchdog_tick_cron.py` 的调度项改为 `pipeline_tick_cron.py`，`watchdog_tick_cron.py` 保留作回退。执行前需 `moon build --target js` 重建 `_build/js/debug/build/cmd/main/main.js`（本次已重建）。

## 五、遗留与建议

1. `cron-auto` 现存 16 个「待领取」堆积任务：新机制下不会再新增堆积，但存量需执行侧（`execute_cron.py` 每轮 1 个）逐步消化；如需批量作废/归档，建议单独决策。
2. 元提示词实例同步：`C:\Users\victo\watchdog_meta_prompt.md` 已作为模板同步至 `templates/pipeline_meta_prompt.md`；Pentad 实例 `Gen_Prompts/_meta_prompt.md` 的替换涉及覆盖，待确认后执行。
3. 建议后续在 `pipeline_tick` 增加堆积治理策略（如超过 N 轮未领取即在途任务自动归档），本次未实现。

## 六、涉及文件

- 新增：`src/ops/ops_pipeline.mbt`、`src/ops/ops_pipeline_test.mbt`、`pipeline_tick_cron.py`、`templates/pipeline_meta_prompt.md`、`reports/2026-09-20-pipeline-watchdog-state-machine.md`
- 修改：`src/engine/engine.mbt`（first_free_root_id + cold_publish）、`src/server/server.mbt`（注册 pipeline_tick）
- 本轮未改动：`watchdog_tick_cron.py`（工作区另有此前会话留下的改动，保留作回退）、`execute_cron.py`、`src/ops/ops_watchdog.mbt`
*（内容由AI生成，仅供参考）*
