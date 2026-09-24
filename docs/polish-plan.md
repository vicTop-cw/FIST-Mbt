# FIST-Mbt 打磨完善计划（初稿）—— 冲刺 2026 MoonBit 九月黑客松 TOP 10

> 定位：用 **fist-mbt 自身的自驱式（selfdrive）、递归拆解（task_plan_deep）** 来打磨本项目自身。
> **自我迭代的过程本身就是交付给评审的 DEMO**。
> 硬性标准：**无硬编码 / 无任何回归 / 测试全绿 / 功能兼容 / 文档即实现**。

---

## 一、结论先行：还差什么才能进前 10

工程底子已经很硬（135 测试、JS+Native 双端全绿、57 工具、CI、文档齐、跨环境可复现）。
真正可能拦住前 10 的不是"技术含量/完成度"，而是 **"让评审几分钟内看懂它值这个分"的叙事与可演示证据**。按影响排序的 5 个瓶颈：

| # | 瓶颈 | 一句话 |
|---|---|---|
| A | **缺一句话卖点** | README 是说明书，评审 GET 不到"为什么 MoonBit 非它不可" |
| B | **缺端到端可演示 DEMO** | 57 个工具只是名字，评审看不到"它真的能跑/能自我推进" |
| C | **CI native 仍是 best-effort** | 已 135 全绿却 `continue-on-error`，自相矛盾，可信度打折 |
| D | **低门槛可复现** | Node≥24/首次 update/native 配置未在最显眼处，评审跑不通=白搭 |
| E | **边界未主动自曝** | node 实验警告、native 配置复杂度未写清，评审现场踩坑减分 |

---

## 二、方法论：自我迭代 = DEMO

不手动一条条改，而是真正用 fist-mbt 自驱能力推进，形成"项目用自身功能自我打磨"的证据闭环：

```
selfdrive_review（审视报告 Next Tasks）
   └─ selfdrive_publish_next（并行发布独立根任务 A-E）
        └─ task_plan_deep（AO 递归拆解成子任务树）
             └─ claim / execute / submit / verify（认领→执行→提交→验收）
                  └─ 通过后归档 → 触发下一轮审视（循环收敛）
```

评审看到的就是：**一个任务编排系统用它自己的审视报告、幂等发布、递归拆解、九态闭环，把自己打磨到可交付** —— 这既是结果也是活 demo。

---

## 三、迭代路线（每项 = 自驱根任务，可独立闭环）

### A. 一句话卖点 + 定位叙事（高优先）
- README 顶部 3 行内落死定位："纯 MoonBit 重写 FIST 指挥官体系 + MCP 化，发布→认领→拆分→执行→验收→归档全闭环，自驱审视、DGM 演化、Omega 强验证、跨进程看门狗——一个可由 AI/定时器持续推进的自治任务编排底座。"
- 与现有 agent 编排（core / lindy / 自研 MCP）的差异化说明 + 为什么 MoonBit。

### B. 端到端自驱 DEMO walkthrough（高优先）
- 一键演示：`moon run cmd/cli` 跑完 publish→…→archive 完整 trace。
- 一份真实运行留存 `docs/selfdrive-walkthrough.md`：审视报告 → Next Tasks → 发布 → 幂等跳过，证明"能自我推进一轮"。
- 可选 GitHub 顶部 GIF / 录屏。

### C. CI native 必绿 + 补 Windows 轨道（中优先）
- 去掉 `ci.yml` native job 的 `continue-on-error`（已全绿）。
- 新增 Windows 轨道（runs-on windows + 配 sqlite3.lib），坐实"JS+Native 双端全绿"卖点。

### D. 低门槛可复现（中优先）
- 环境要求（Node≥24 / 首次 `moon update` / native 需 sqlite）移到 README 最显眼位置。
- 提供 `moon run cmd/main` 后 10 秒自检通过的 smoke/自检入口。

### E. 主动自曝边界（低优先）
- 文档写明：`node:sqlite` 实验警告、native 配置复杂度、已知遗留 —— 为什么、怎么绕。

---

## 四、验收标准（每次子任务回传必过）

1. **无硬编码**：源码/smoke 无 `[A-Z]:`、`/home/`、`/Users/` 等绝对路径；路径均相对/参数化。
2. **无回归**：`git diff` 仅涉及本任务声明的文件；既有 136 测试不受影响。
3. **测试全绿**：`moon test --target js` 且（若涉及 native 相关）`--target native` 均 136/136。
4. **功能兼容**：不改变既有 MCP 工具的参数/返回/语义（新增可，破坏不可）。
5. **文档即实现**：README/USAGE/AGENTS/docs 与实际行为一致；改了实现必须同步改文档，反之亦然。

---

## 五、本计划落地方式

- 用 `selfdrive_publish_next` 把 A–E 作为 5 个独立根任务发布进自驱命名空间；
- 每个任务经 `task_plan_deep` 递归拆解后，在认领/执行/提交/验收中完成并归档；
- 每完成一项，`selfdrive` 审视其成果，收敛到下一轮；全部完成即"文档即实现"的最终态验收。

*初稿由指挥官拟定，交 fist-mbt 自驱推进。*
*（内容由AI生成，仅供参考）*