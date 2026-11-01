# 报告 · 第二轮 bug 清扫批（2026-11-01）

## 结果摘要

- **BUG-523 / 531 / 516 三条翻 FIXED**；新发现并登记 **BUG-536**（待 owner 决策）。账面 536 条入账，OPEN 仅余 2 条（527=WIP 车道自持，536=owner 决策）。
- BUG-523（账实拆单）：CI 41284830056/41284830060 双绿于 8da9f920b，native 两臂干净树全过 ⇒ BUG-133 两格关闭条件齐。车道 2fbf0f820。
- BUG-531（vools 探针概率崩）：4 处 metadata 读点收进模块级 `_METADATA_READ_LOCK`（vools c6bf905）；回归锁=删打桩维度，3 连发 pytest EXIT=0。
- BUG-516（hermetic 棘轮误伤现状面标定）：校准档 C 落地（车道 88968eb37）——被检尺自声明 `HERMETIC_CALIBRATION={锚点名:理由}`，纯读命中记 C 只记账不顶棘轮；W/G 不可校准。R 92→84，BASELINE 不动。变异格 C3/C5/C9 证明不吞真违例。
- BUG-536（新，medium）：fist-bug-sync 定时作业 5/5 连红；两段根因（master 落后 main 132 笔且无构建步、secrets 缺 FIST_GITHUB_TOKEN）都在远端仓库状态，出路 A=owner 确认后 ff 推 master、B=owner 配 secret。

## 资源消耗

- 统帅 1（本会话）：分流、终审、账本落笔、汇报。
- 后台车道 4：BUG-523 核验、BUG-531 修复、BUG-516 修复、计划面巡检。
- 工具面：fist-mbt MCP 仅 health_check（连接器 cwd 不指向本仓，写型 RPC 全避开，见 memory「写型 FIST RPC 先验台账身份」）；gh api 匿名读 CI；全部账本编辑走 temp/*.py 字节脚本（LF + 断言 + 用后即删）。

## 任务分配记录

| 车道 | 任务 | 交付 | 终审结论 |
|---|---|---|---|
| L1 | BUG-523 CI 双跑核验 | 2fbf0f820 + FIXED 段 | 过（引 run/job id 齐全）|
| L2 | BUG-531 vools 锁 | vools c6bf905 | 过（3 连发 EXIT=0；vools 未推留 owner）|
| L3 | BUG-516 校准档 C | 88968eb37 | 过（BASELINE 未动，父提交逐字核对）|
| L4 | 计划面巡检 | 阻挡地图（无代码）| 过（结论并入遗留）|

## 遗留风险

- BUG-536 待 owner 决策（A=ff 推 master / B=配 secret），定时作业会继续每 30 分钟红。
- c0795ded6 的本机 cl7 PASS 读数与 CI 矛盾，归因未闭合；已按判例以 CI 干净树为准，陈旧投影由 9b9f35a04 修正。
- BUG-516 棘轮 92 里其余判据的标定债仍在，各自待自声明收账。
- vools c6bf905 未推（兄弟仓，推权留 owner）。

## 后续建议

1. owner 拍板 BUG-536 出路 A/B（A 零损失已验祖先关系）。
2. WIP（BUG-527）收口后按阻挡地图派计划车道：CAF §2.3 接线 / OFM fallback 重试 / Tier2 PR3 / web 面板健康合并 / Reminder 角色；Tier2 PR2 与 PR3 成对派。
3. 各 hermetic 判据轮到自己被检查时自声明校准，逐步把 R 84 收干净。

## 超额内容

无（计划面巡检属本轮目标内）。

## 来源

- 车道车道回执 4 份（BUG-523 / 531 / 516 / 计划巡检），commits：2fbf0f820、vools c6bf905、88968eb37。
- CI runs：41284830056 / 41284830060（8da9f920b）；BUG-536 定时作业 runs 40664602973~41296809919。
- 账本落笔 commits：e464c98e3（532追记2）、c0795ded6（536）、9b9f35a04（531）、dfd585174（516+README）。
