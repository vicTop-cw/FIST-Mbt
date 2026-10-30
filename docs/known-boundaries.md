# FIST-Mbt 已知边界（Known Boundaries）

> 本文档是面向外部评审的**自曝面**：明确列出项目「不做什么」「不能做什么」「已知但未修的缺陷」。
> 目的不是遮掩，而是让评审在看交付物之前就知道边界在哪——这比藏起来更可信。
> 最后更新：2026-10-23

---

## 1. 平台与后端

### 1.1 Native 后端不是稳定门槛

- **权威稳定门槛 = JS 后端**（Node.js ≥ 24，`moon test --target js`）。
- Native 后端（`moon test --target native`）在干净树 `git archive HEAD` 上会被依赖 `mizchi/sqlite` 的 FFI 打死（账本 **BUG-133**）。
- CI 的两条 native 臂已改为「常驻判据当门 + 门后才跑全量」：门 = `scripts/blackbox/e2e_native_heap_probe.py`（`--selftest` + `--runs 12`），只有 `crashes=0/12` 才放行全量测试。
- 该判据是**抽检**不是关闭条件：`crashes=0/N` 只说明「这一支样本没抽中」，不等于「native 已修」。
- **结论**：如果你要跑 native 测试，请在 Linux 环境下跑；Windows native 不稳定是已知的。

### 1.2 `moon test` 退出码不可靠（BUG-142）

- moon 0.1.20260920 实测：测试可执行文件被 SIGABRT 打死时，`moon test` 仍回 exit 0。
- **判绿必须解析 `Total tests: N, passed: N, failed: 0` 汇总行**，exit 0 只是必要条件。
- 本项目所有测试入口（`scripts/moon_test_env.py`）都已按此口径收口。

### 1.3 Windows 工具链缺陷

- moonc 在 Windows 上对 `\\?\` 长路径前缀会 ICE（`Sys_error("\\\\?: Invalid argument")`）。
- 本项目已通过 `MOONC_OVERRIDE` shim（`~/.moon-shim/shim.exe`）绕过，但**这是本机修补，不是 moonc 修复**。
- `moon fmt --check` 在本机不可用（BUG-388），格式门以 CI（Linux nightly）为准。

---

## 2. 功能边界

### 2.1 多语言 SDK 矩阵已砍掉

- Plan v0.2 已裁决：**不产出任何语言 SDK / 桥接包**。
- 语言侧统一走 HTTP 协议 + `docs/examples/` 示例。
- 这不是「还没做」，是「决定不做」——砍掉是为了聚焦核心能力。

### 2.2 WT-01 / SHIP-02 等人裁

- **WT-01（claimguard 挂 claim/publish 钩子）**：plan 明写「owner 决策后执行」，前置 BUG-157 已修但接线面待裁。副机不代裁。
- **SHIP-02（GitCode release upload）**：plan 说「刻意不盲落」，需要 owner 确认发布策略后才执行。
- 这两条不是「未开工」，是「等人裁」——协议层决定不能由副机代做。

### 2.3 部分功能只做了一半

以下功能处于「部分」状态，验收标准未完全满足：

| 功能 | 已完成 | 未完成 |
|---|---|---|
| CAF-01（执行结果回写） | executor_run 返回结果 | 未回写 caf_memory（写半） |
| CAF-02（CafMemory to_json） | 基础 JSON 序列化 | 原始 records 字段补充 |
| WEB-01（任务看板） | 任务树 + 详情面板 | DAG 可视化未渲染 |
| SHIP-01（GitCode Releases API） | 端点探测 + fallback | 发布侧未接 |
| POLISH-02（selfdrive-walkthrough） | 文档存在 | 读数陈旧未更新 |
| POLISH-03（CI native job） | native 臂存在 | release 臂被 R8 钉住 |

---

## 3. 文档与计数

### 3.1 文档计数落后于实测（历史，已由判据守住）

- 曾有一批文档把「工具数 / 测试数」写死在正文里，工具或测试一增长就腐烂。
- **根因**：`moon update` 后新增依赖 / 新增工具，但文档计数未同步 —— 这是「文档即实现」规范的自检缺口。
- **现状**：这两个数已由判据逐份守住（`scripts/check_tools_sync.py` 的 R3b/R7 扫声明形状；测试数以汇总行为准）。**文档不再抄第二份读数**，需要数字请直接跑判据。
- **教训**：写死数字必腐烂；文档里只该写「去哪拿这个数」，不该抄「这个数是多少」。

### 3.2 插件目录未在真实宿主验证

- 四宿主插件目录（atomcode / codearts / deepseek-harness / claude）是**生成投影**，由 `scripts/gen_plugins.py` 从单一真源产出。
- cl7 守卫（`scripts/check_plugin_sync.py`）只保证「等于投影」，**不保证「宿主可用」**。
- 四宿主的真实装载验证不在 CI 覆盖范围内。

---

## 4. 守卫与判据

### 4.1 电池有预存红

- `run_guards` 电池有 **6-9 格预存红**（多轮积累的存量债）。
- 这些红格**不是产品功能缺陷**——`moon test` 全绿（1983/1983），红的是工程纪律面的守卫。
- 主要预存红：`check_scripts_index`（5 个脚本未登记）、`check_doc_dup`（scripts/README.md 冗余）、`check_unit_number_unique`（历史撞号未进基线）、`check_battery_count_doc`（计数漂移）。

### 4.2 `project_standards` 不支持自定义规则

- `project_standards` 工具**没有 `extra_rules` 参数**，`project_type` 仅是上下文标注。
- 项目自定义规则只能写在 `AI-DEVELOPMENT-STANDARD.md` 里，不能通过工具参数注入。

### 4.3 文档语义无自动守卫

- `check_doc_surface` 只比对**结构与计数**（J2/J3/J4/J6/J7/J8），不验证**语义**（比如 skill 里那句"用途"是否名副其实）。
- 语义正确性靠人工终审 + `check_doc_surface` J8 的调用面比对。

---

## 5. 赛事相关

### 5.1 mooncakes.io 发布未完成

- MoonBit 赛事验收要求「mooncakes.io 发布」，本项目有 `.mooncakes` 打包配置但**尚未发布到平台**。
- 这是验收硬指标，发布前不能算「通过验收」。

### 5.2 演示可复现性需打磨

- `award_demo.py` 可一键跑通演示，但 README 首屏叙事和 30 秒演示脚本尚未打磨到「评审一眼看懂」的程度。
- 创意/生态价值维度（30% 权重）的叙事重构正在进行中。

---

## 6. 一句话总结

> **技术底子是冠军级的**（170+ MCP 工具、1983 测试全绿、DAG/Phi Accrual/Saga/MC 全栈），但**文档计数落后、native 不稳定、mooncakes 未发布、演示叙事待打磨**——这些是最后冲刺阶段要补的硬伤，不是架构缺陷。

---

*（内容由 AI 生成，仅供参考）*
