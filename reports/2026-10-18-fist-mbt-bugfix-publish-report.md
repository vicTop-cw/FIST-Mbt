# 2026-10-18 · FIST-Mbt 寻虫-修复-打磨-验证闭环 + 发布 0.3.9 收口报告

> 触发：owner 指令对 fist-mbt 走一轮「寻虫-修复-打磨-验证」后推送仓库并发布。
> 前置基线：master 合并 marvis-verify-20261017（多租户隔离/军衔体系/CAF标准3），moon test EXIT=0，ahead origin/master 292。

## 1. 结果摘要

| 项 | 结论 | 证据 |
|---|---|---|
| BUG-261 | FIXED（OPEN→FIXED，bugs.md 已标） | 提交 626bc46 |
| BUG-262 | FIXED（OPEN→FIXED，bugs.md 已标） | 提交 626bc46 |
| BUG-268 | FIXED（本轮收口补充 evidence） | 提交 626bc46 |
| moon fmt | 通过 | fmt --check exit=0 |
| moon test | 1302/1302 通过，failed 0 | --target js -j 4 |
| issue_scan 复扫 | 126 文件 9721 findings，medium 6→0（substring-overrun 0 条），无真阳性误豁免 | file-agent 复验 |
| 版本 | 0.3.8 → 0.3.9（三处真源同步） | 提交 8052e67 |
| moon publish | 200 OK，注册表 Latest = 0.3.9 | temp/publish.log |
| push | GitHub(origin) + GitCode 的 master 与 tag v0.3.9 均到位 | git ls-remote 双侧确认（tag 8b6f14eb） |

## 2. 修复内容

| Bug | 文件 | 修法 |
|---|---|---|
| BUG-261 | scripts/blackbox/e2e_irm_line.py | probe() 真面档弃用 `[ -x 'fist' ]` 裸词，改 `_find_posix_shell()` 定位 Git Bash/MSYS 并点名 shell，`_is_wsl_bash()` 排除 WSL bash；两者皆无时 REJECT(rc=3)。沙箱档 `-x` 保留。 |
| BUG-262 | scripts/blackbox/e2e_irm_line.py | real() 双保险：`_userprofile_redirected()` 检测 USERPROFILE 不一致即 return 2 拒绝；finally 采集真实 PATH 与 .local\bin 四件 shim sha8 基线，跑后逐字比对还原。 |
| BUG-268 | src/server/issue_scan.mbt | 守卫检测扩展：substring 实参括号深度感知、for 头尾部括号修剪、近邻守卫窗口 6→12 行；识别 x%k 不变量与 if var>k 对 find()/length()-k 的间接长度。 |

## 3. 验证

- `moon test --target js -j 4`：Total tests 1302, passed 1302, failed 0（版本 bump 后回归锁仍绿）。
- `moon fmt --check`：exit=0。
- `moon publish --dry-run`：202 Accepted（0.3.9）。
- `moon publish`：Check passed → Server status: 200 OK。

## 4. 发布链路

1. 版本三真源同步 0.3.9：`moon.mod` / `src/server/server.mbt:795 project_version` / `cmd/cli/help_topics.mbt:6 FIST_VERSION`。
2. mooncakes.io 注册表：`moon view --versions` 首位 0.3.9（Latest）。
3. 推送：origin(GitHub vicTop-cw/FIST-Mbt) 与 gitcode(GitCode VictorTop/Fist-Mbt) 的 master 均已同步（ahead 归 0），tag v0.3.9 双侧一致（8b6f14eb9f15298b9b3834cceb8561d77743dcb1）。
4. GitHub Release 由 push tag 触发 release.yml（meta/build-js/release），资产名 fist-mbt-js-v0.3.9.zip。

## 5. 提交

- `626bc46` fix(e2e_irm_line+issue_scan): BUG-261/262/268 修复 + 报告（3 files, +160/-28）
- `8052e67` chore(release): bump version 0.3.8 -> 0.3.9（3 files, +3/-3）
- 工作区干净。

## 6. 遗留

- moon publish 校验过程存在 2014 条 deprecated/unused 警告（`is_some()` → `x is Some(_)` 等），不影响发布，可后续打磨轮处理。
