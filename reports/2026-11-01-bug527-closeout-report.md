# BUG-527 收口批 · 统帅接手轮报告（2026-11-01）

## 结果摘要

- BUG-527 前一轮收口（`d43a06a28`，出路①：库包摘 link）被 CI **当场证伪**：两条 native 臂红——
  native 测试 exe 链接 `undefined reference to sqlite3_*`（runs 41305804775 / 41305804754）。
- A/B 实证定案：带 link 的 `8da9f920b` 同两臂绿（runs 41284830056 / 41284830060）⇒ CI nightly moon
  需要**库包**把 `-lsqlite3` 传下去给测试链，而本地 moon 0.1.20261021 把带 link 的库包当可执行目标
  去链 ⇒ 两个 moon 世代语义相反，单侧整改在另一侧必红。
- 处置：`8a669992d` 回滚 14 份库包 `moon.pkg` 到 `e0ef45c5e` 状态（link 恢复）；账本**追记2**改判
  「工具链版本语义分歧」，出路②（上游 issue）/③（native 观测臂降级为只建可执行包）待裁决，
  **单保持 OPEN**；AGENTS.md native 段同批改回实证口径。
- 同批补登 battery 登记锚点 `scripts/README.md` 147→148 / 106→107 / 119→120（`b4d50affa` 新增
  `check_ofm_endpoint.py` 漏登，CI 04775 的 JS ubuntu 臂 battery guard 当场抓，判例-5 族第五次）。
- **终审 CI（8a669992d）= 全绿**：runs 41306763867（CI：js/windows、js/ubuntu、native/ubuntu）与
  41306763838（FIST CI：js/ubuntu、native/ubuntu）全部 success，native 两臂转绿、battery guard 转绿。
- BUG-536 出路 C 已先行落地（`e0ef45c5e`：fist-bug-sync.yml schedule 停用）；BUG-537 由巡逻车道
  修复面经终审后入库（`b4d50affa`）。

## 资源消耗

- 模型：Qoder 主会话统帅（本报告）+ 2 个后台子代理（评估车道、CI 看守）。
- 工具：git / python（字节脚本）/ GitHub Actions 匿名 API / Bash。
- CI 看守子代理耗时约 17 分钟（其中 16 分钟耗在一个被短 SHA 骗过的探针上，见「遗留风险」）。

## 任务分配记录

| 分派 | 内容 | 回传 |
|---|---|---|
| 评估车道（后台子代理） | 停摆 10 小时的 61 文件 WIP 接手判定 | 18 真实文件、moon check 0 error、JS 2004/2004，判干净收口候选 |
| 统帅亲做 | d43a06a28 收口 → CI 证伪 → 8a669992d 回滚批次（14 moon.pkg + bugs.md 追记2 + AGENTS.md + 锚点补登） | 落盘面 17 件与申报面逐字相等 |
| CI 看守（后台子代理） | 盯 8a669992d 判定并取 annotation | 全绿 3+2 job；另带出短 SHA 探针教训 |

## 遗留风险

- **BUG-527 保持 OPEN**：本机 moon 0.1.20261021 全项目 native build/test 必崩（CI nightly 可用）。
  出路②提上游 issue / 出路③把「native 全项目构建」格降级为只建可执行包——择一待 owner 裁决。
- **CI 探针短 SHA 雷（判例-35 族新增实锤）**：GitHub Actions API `head_sha=<短SHA>` **静默返回
  `total_count: 0` 不报错**（commits API 却认短 SHA）；看守代理被它白耗 16 分钟。凡按 SHA 查 runs
  必须用完整 40 位。
- GitCode 容量红线（repo 2.4 GiB > 1.0 GiB）：本次推送仍被放行，但 remote 已警告后续可能拒推。
- FIST_OFM_ENDPOINT 已改 18326（owner 授权 setx），但 relay 服务本身未起（WinError 10061），
  探活读数 1——是否查启动方式待 owner 答复。

## 后续建议

1. 裁决 BUG-527 出路②/③（本轮账本追记2 已把两条路写清，随时可派）。
2. 计划面阻挡已随 WIP 收口解除：CAF §2.3 接线 / OFM fallback retry / Tier2 PR2+PR3 /
   web-health 合并 / Reminder 角色可进下一批派单（派单前照例查 git status 占用面）。
3. GitCode 仓库瘦身（Compact）宜尽早，避免下一次推送被容量红线硬拒。

## 超额内容

CI 看守代理在等待期间反向取证了「短 SHA 静默 0」这一探针失效模式，已入本报告遗留风险并同步
记忆面——属顺带收获，非计划内工作。

## 来源

- CI runs：41305804775 / 41305804754（红，证伪）、41284830056 / 41284830060（绿，对照）、
  41306763867 / 41306763838（绿，终审）。
- 提交：`d43a06a28`（前轮收口，被证伪）→ `8a669992d`（回滚批次，本轮权威面）。
- 账本：memory/bugs.md BUG-527 追记2（2026-11-01）；当日日志 memory/2026-11-01.md「BUG-527 收口批」段。
