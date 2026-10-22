# 2026-10-20 副机首单汇报 · BUG-324 迁移器指路自检 + ICE 分流

## 结果摘要
- 副机接入：gitcode → 本地 master 纯快进覆盖（0.2.3 → 0.3.9 / v0.3.9），无孤儿提交、无丢失。
- 修复 `scripts/migrate_mooncakes_modjson.sh` 两处自坏：兜底分支反引号被 bash 当命令替换（`line 64: Error:: command not found`，指路正文被吃）；编译器 ICE 误判为「源码编译错误」，把人往改源码带。
- 新增 `--selftest` 七格合成对照 + ICE 独立分流格。

## 资源消耗
1 个 bash 脚本（+~75 行）、账本 2 条（BUG-324 FIXED / BUG-325 OPEN）、scripts/README.md 1 处、memory 日志 1 份、本报告 1 份。未动 MoonBit 源码、未动 workflow。

## 任务分配记录
副机亲自做：分流决策（先跑本仓正解 `migrate_mooncakes_modjson.sh` 而非另写迁移器，避免重复造轮子）、根因定位、终审证据。可下放的具体工作本轮量小未下放。

## 验收证据（实测，非自述）
- 修复前真实复现：`migrate_mooncakes_modjson.sh: line 64: Error:: command not found` + 把 ICE 指成「源码编译错误」。
- 修复后：`bash scripts/migrate_mooncakes_modjson.sh --selftest` → 7/7 绿；真 `moon check --target js` 的 ICE 改判 `[编译器 ICE／工具链缺陷]`。
- 变异对照（把反引号改回去）→ `SELFTEST FAILED: 1/7 格红`、rc=1：锁是活的。
- 退出码纪律不变：合成与真实 ICE 均 rc=1，非迁移错误照透传。

## 遗留风险
1. **本仓 MoonBit 门禁在副机不可自证**：本机 moon 0.1.20261016 / moonc v0.10.16 对每次编译调用 ICE（`\?\` 长路径），与项目无关；`cli.moonbitlang.com` 出口 403（Windows 与 WSL 同）⇒ 钉不回本仓钉版 0.1.20260920、也升不动。故 `moon fmt/check/test` 的「零 WARNING/ERROR」这一硬门，本单只能由 CI 兜。
2. BUG-325（OPEN，等 owner）：`scripts/run_check_t0r21.py` 在跟踪面带他人机器绝对路径且未登记 README ⇒ `check_scripts_index.py` 在干净 HEAD 上恒红。删除他人跟踪文件不可逆，副机不代删。
3. `--selftest` 尚未挂 CI（按本仓「判据不挂 CI 等于没锁」应当挂）；workflow 改动本机无法验证，留下一单。

## 后续建议
- 副机侧解法二选一：给一台 moon 0.1.20260920 的钉版工具链（离线包），或放开 `cli.moonbitlang.com` 出口。
- 开 PR 需令牌或 `gh`/GitCode CLI：副机两者皆无 ⇒ 本轮只推分支并给出 compare 链接。

## 超额内容
无（未新增功能、未重构邻域）。

## 来源
`scripts/migrate_mooncakes_modjson.sh`（本仓 2026-10-13 迁移器与分流表）、`AGENTS.md`「Tooling / 一源四态·插件态」、`memory/bugs.md` BUG-132/142/127 同族纪律、副机本机 moon/moonc 实测输出。
