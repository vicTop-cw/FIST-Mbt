# R89 汇报：概率式故障检测 phi_accrual（Hayashibara 2004 经典算法落地）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：20260926.cost-market-routing.md 五信号全落地后开新调研线程（BACKLOG P3「Phi Accrual 概率式检测」）——把 watchdog/heal 的固定 timeout 升级为"按心跳间隔历史分布算怀疑度 φ"。
- **达成**：新增 `phi_accrual` 工具（90→**91**）：engine 自由 pub 函数纯计算——φ=-log10(P(心跳晚于 elapsed 到达))；窗口内间隔均值 μ+样本标准差 σ（Bessel 校正）；σ≈0 回退指数分布 φ=elapsed/μ·log10(e)；正态建模 z=(elapsed-μ)/σ，|z|<3 用 A&S erf 近似、|z|≥3 用尾部渐近展开保深尾部精度；core 无 sqrt 用牛顿法自实现；engine moon.pkg 加 moonbitlang/core/math（exp/log10）；φ≥threshold(默认 8,原论文口径) 判 suspect 否则 healthy；无间隔历史 insufficient；尾部下溢饱和 999。server 复用 intlist 零新依赖。
- **验收**：`engine_phi_test.mbt` **+3**（σ=0 指数回退：elapsed 5s→φ≈0.434 健康 / 100s→φ≈8.686 怀疑；正态建模 μ=10/σ≈3.54：z=5→φ≈6.5 健康 / z=6→φ≈9.0 怀疑；单调性 + 空历史 insufficient）；全量 **256→259/259**（+3）；mcp_smoke 91 工具；award_demo ⑧ 段加 R89 演示行（实测 φ=44.98 verdict=suspect）**PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（259/259）+ mcp_smoke（build 后 91 工具）+ award_demo（R89 段）+ 守卫族 + cleanup。
- 变更：engine_phi.mbt(+新文件 ~150 行) / engine/moon.pkg(+math 依赖) / engine_phi_test.mbt(+新文件 3 测试) / server.mbt(工具注册+intlist+map 组更新) / README/AGENTS(运维组 6→7)/deliverable(R59)/USAGE(§6.3)/agent-map/scoring_rubric/mcp_smoke expected 91/BACKLOG(锚点+Phi 行 done)/申报书(§6 补 50 行)/memory 调研档 20260926.reliability-phi-accrual.md（新建）/award_demo(R89 行)。

## 三、任务分配记录
- R89 属轻量单函数硬能力 + 3 测试 + 文档同步，指挥官亲自做，未开子任务。

## 四、遗留风险
- φ 计算为独立原语（显式 intervals 入参）；心跳间隔历史尚未持久化（store 仅 last_seen），watchdog/heal 端到端消费 φ 判活为后续项（默认关闭零回归）。
- 正态假设为 Phi Accrual 原论文口径；|z|≥3 尾部用渐近展开（z≥4 相对误差 <1e-3），已实测 5σ/6σ 判决正确。

## 五、后续建议
- 下一候选：心跳间隔历史持久化（新表 heartbeat_history）+ watchdog 端到端 φ 判活（默认关闭），把"概率式看护"从原语升级为运行时行为；或英文 README（P3 国际受众）、门禁复评确认 R87-R89 增量。

## 六、超额内容
- 无超额；改动严格限定概率式故障检测原语家族（含调研档留档，属"调研先行"惯例）。

## 七、来源
- `src/engine/engine_phi.mbt` `phi_accrual`/`sqrt_approx`/`erf_approx`/`normal_tail_q`（R89）
- `src/engine/engine_phi_test.mbt` R89 三用例
- `src/server/server.mbt` phi_accrual 注册 + intlist
- `memory/research/20260926.reliability-phi-accrual.md`（调研档：Hayashibara 2004 IEEE/SRDS，Cassandra/HBase 生产采用）
- `scripts/award_demo.py` ⑧ 段 R89 行
