# 2026-10-22 · v0.3.10 升版对齐（fix/version-align-r2，金条五）

**做了什么**：风语者把 master 推到 v0.3.10 后，5 把守卫尺预存红（host-installable / doc-surface / release-asset-names / scripts-index / plugin-sync）。本单按「从主仓开新分支修复」的规矩在 `temp/wt-align` 隔离 worktree 收口：
1. `.dsh/fist-mbt-plugin/package.json` version+description 0.3.9→0.3.10
2. `USAGE.md:3` 自述版本、`README.md:141` 离线线资产名字面量 → 0.3.10（R13 面）
3. `scripts/README.md` 补登记 4 把漏网尺（fist-gate / whisperer / check_bug_refs / fist-pr-automator）
4. `gen_plugins.py` 重投影 → 实质改动 13 个插件文件（其余 42 个是 CRLF 噪声未入库），plugin-sync 逐字节 PASS

**终审（金条八实跑）**：5 把尺逐一 rc=0；提交态复验 plugin-sync rc=0；工作树 0 src 污染、0 残留脏件。

**可复用教训**：
1. **升版是「面事件」不是「文件事件」**——一次版本号前进要同时过 .dsh manifest、USAGE/README 字面量、插件投影、scripts 索引四类面；靠人记必漏（本次 4 把尺红全是不同面的漏）。
2. **`M` 状态不等于有实质改动**——autocrlf 下未改内容的文件也标 M；`git add -A` 后 git 自己归一化，17 文件才是真改动。核对暂存区要用「边界白名单过滤 + 计数」而不是逐行看 status。
3. **电池在本 worktree 冷编译巨慢**（无 `_build/`，moon 系尺每发都要全量 build）——本地终审以 per-guard 直跑 + 提交态 plugin-sync 为决定性证据，全量电池交 CI 守卫臂；不为此多烧 20 分钟。

**边界**：0 个 `.mbt/.mbti/moon.pkg`；plugins 面全部由生成器产出、无手改。
**遗留**：BUG-354（10 个 ~/? 参数从不消费）、BUG-361（Json::value 430 处形态决策）、BUG-362（编译器少报 11 处）、BUG-364（agent-map 分组表覆盖缺口）——全部属 owner 决策面，不在本单。
