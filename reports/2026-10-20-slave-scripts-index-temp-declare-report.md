# 2026-10-20 · 副机 · scripts 索引守卫恒红收口报告（BUG-327）

## 结果摘要
`python scripts/check_scripts_index.py` 在干净 HEAD 上恒红（rc=1），红源是跟踪面里的孤儿一次性脚本
`scripts/run_check_t0r21.py`。按其性质（硬编码他人机器路径 + 写死 `passed: 162` + 全仓零引用）走守卫
自设的临时件通道改名为 `_run_check_t0r21.py`，不改内容、不删文件。修后 rc=0 PASS。分支
`slave/misc/scripts-index-declare-oneshot-temp`，base 与 master 同点。

## 资源消耗
- 会话轮次：约 4 轮；命令 6 条（守卫复跑 ×2、grep 引用 ×2、改名 ×1、账本追加 ×1）。
- 无 moonc 参与：本单全程纯 Python，与本机工具链 ICE/迁移无关，属可即时自证的一类任务。

## 任务分配记录
指挥官（本会话）自持：定性、选路（登记 vs 改名 vs 删除）、执行、判据复跑。未派子代理——
单文件改名 + 一条守卫判据，派单成本高于做单成本。

## 遗留风险
1. **重复账本**：同一缺陷在并行分支 `slave/fix/migrate-selftest-ice-routing` 记为 BUG-325（OPEN）。
   两条 MR 都合时，`memory/bugs.md` 与 `memory/2026-10-20.md` 会文本冲突；以本条 FIXED 为终态、
   BUG-325 转 DUPLICATE 即可，冲突只涉及文档面。
2. **文件仍在跟踪面**：改名只是把它从「正式工具」降级为「临时件」，`即用即清` 这条纪律目前无人代跑；
   彻底删除需要你拍板（删除不可逆）。
3. **守卫无自检**：`check_scripts_index.py` 没有 `--selftest` 分支，它的「红」靠本次真实 FAIL→PASS 佐证；
   若要让锁常驻，可给它补一格变异对照（本单未做，属超范围）。

## 后续建议
- 若要根治：把 `_` 前缀件的存留期纳入看门狗/巡检（例如存在超过 N 天即点名），否则 `temp 区` 会长草。
- 三条 slave 分支建议按 `misc → fix(migrate) → fix(moonc)` 顺序合，文档面冲突最少。

## 超额内容
无。改动面严格等于：改名 1 个文件 + `memory/bugs.md` 追加 1 条 + 当日日志 + 本报告。

## 来源
- 判据原文：`scripts/check_scripts_index.py:35-47`（formal_scripts 的 `_` 前缀豁免）、`:62`（FAIL 文案）。
- 复现与复绿读数：本会话两次 `python scripts/check_scripts_index.py`（rc=1 → rc=0）。
- 该件身世：`git log --oneline -- scripts/run_check_t0r21.py` → 98fb27a 单次带入，之后无人引用。

*（内容由 AI 生成，仅供参考）*
