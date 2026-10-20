# FIST-Mbt 副机（Slave Agent）开发操作守则

> **身份**：你是副机，主机是 FIST-Mbt 的主仓 owner。你的代码**永远不会直接合并进主仓**，只会以 PR 形式提交给主机审核。主机是唯一能动主仓 default 分支的实体。
> **目标**：自主迭代 FIST-Mbt 的功能缺口，每个功能缺口开一个独立分支、写完整四态、提一个 PR，不依赖主机实时指导。
> **下载后第一步**：读完本文件 → 按 §1 克隆主仓 → 按 §5 认领一个缺口开始开发。

---

## 0. 先搞清楚你在什么版本上开发

### 0.1 主仓当前基线（必须精确匹配）

| 项目 | 值 | 来源 |
|---|---|---|
| **主仓 URL** | `https://github.com/VictorTop/FIST-Mbt.git` | `git remote -v` |
| **HEAD commit** | `cd6a3630582703e2b2e55a9009b5044d2e14d051` | `git rev-parse HEAD` |
| **moon.mod version** | `0.3.9` | `moon.mod` |
| **moon 工具链** | **0.1.20261016** 精确 | `moon --version`（**必须精确匹配，不要 nightly、不要更旧**） |
| **Node.js** | **≥ 24** | `node --version`（缺 `node:sqlite` 的 `returnArrays` 会退化成对象行） |

### 0.2 环境安装（副机首次 setup）

```bash
# 1. 克隆主仓（不要 fork，直接 clone 再 origin → upstream）
git clone https://github.com/VictorTop/FIST-Mbt.git
cd FIST-Mbt
git fetch --tags
git checkout cd6a3630582703e2b2e55a9009b5044d2e14d051   # 精确钉到基线 commit

# 2. 配置 remote（关键：origin 指向主仓，upstream 指向你自己的 fork）
git remote rename origin upstream
git remote add origin git@github.com:<你的GitHub用户名>/FIST-Mbt.git   # 你的 fork

# 3. 装 moon 0.1.20261016（精确）
# Windows: powershell -ExecutionPolicy Bypass -c "irm https://cdn.moonbitlang.com/moon/0.1.20261016/install.ps1 | iex"
# Linux/Mac: curl -fsSL https://cdn.moonbitlang.com/moon/0.1.20261016/install.sh | bash
moon --version   # 必须输出 moon 0.1.20261016

# 4. 装 Node.js ≥ 24（用你系统的包管理器）
# Windows: winget install OpenJS.NodeJS.LTS
# Linux: curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs
node --version   # 必须 ≥ v24.x.x

# 5. 装 Python 3.x（脚本守卫族依赖）
python --version

# 6. 刷新依赖
moon update

# 7. 基线验证（必须全绿，否则停止开发、提 Issue 给主机）
moon fmt --check
moon test --target js
# 基线应该至少 Total tests: 1346, passed: 1346, failed: 0.
# 如果不是，不要继续开发——你的环境有问题。
```

### 0.3 你**绝对不能碰**的东西（任何情况下）

| 禁令 | 原因 |
|---|---|
| **不能** push 到 `upstream`（主仓） | 你没有写权限，而且主仓不接受直接 push |
| **不能** push 到 fork 的 `main`/`master` 分支 | 所有代码必须走 feature_*/fix_* 分支提 PR |
| **不能**手改 `plugins/` 四宿主目录 | 插件态由 `scripts/gen_plugins.py` 从真源投影，手改 = 下次重跑覆盖 |
| **不能**手改 `.mbti` 文件 | `moon info` 自动生成，手改无意义 |
| **不能**手改 `dist/fist-mbt.js` | 构建产物 |
| **不能**改 `memory/bugs.md` 的**抬头状态**（OPEN/FIXED/DUPLICATE/FALSE_POSITIVE） | 账本状态由 `bug_fix`/`bug_mark_status` MCP 工具改；直接改 Markdown 会让 gen_plugins.py 投影出红账本 |
| **不能**在**没跑过 `moon fmt`** 的情况下 commit | CI 的 `moon fmt --check` 门会红 |
| **不能**在**没跑过 `moon test --target js` 全绿**的情况下提 PR | 主机 MR 前第一件事就是全量测试 |

---

## 1. 分支命名规则（强制）

所有分支必须严格按以下格式命名：

| 类型 | 前缀 | 后缀示例 | 何时用 |
|---|---|---|---|
| **新功能** | `feature/` | `feature/caf-writeback-slice-b` | 纯新增功能、新工具、新模块 |
| **Bug 修复** | `fix/` | `fix/dag-cost-route-tiebreak` | 修 bug（账本有 OPEN 条） |
| **守卫族** | `guard/` | `guard/check-skill-inject` | 新增 CI 守卫判据 |
| **重构** | `refactor/` | `refactor/router-multi-pool` | 不改语义、只优化结构 |
| **文档** | `docs/` | `docs/polish-plan-point-A` | 纯文档改动（README、AGENTS、docs/） |
| **无** | `misc/` | `misc/typo-in-comments` | 什么都不算的小东西 |

**绝对禁止**：直接在 `main`/`master` 上开发；分支名无前缀；分支名用中文；分支名超过 40 字符。

---

## 2. 认领一个缺口开始开发

### 2.1 从主机提供的缺口清单里选

主机维护了两个地方的缺口清单：
- **`docs/2026-10-20-slave-tasks.md`**（本仓根目录，主机每次更新）—— 这是你的**主清单**
- **`docs/` 下各 plan 文档里的 [ ] 勾选项** —— 这些是原始来源，主机已经把它们归并到上面那份主清单里

**选一个你想做的**，然后在那份主清单上把 `[ ]` 改成 `[working]`，commit 一个"认领"的 commit：

```bash
git checkout -b feature/caf-writeback-slice-b
# 编辑 docs/2026-10-20-slave-tasks.md 把 [ ] Slice B ... 改成 [working]
git add docs/2026-10-20-slave-tasks.md
git commit -m "slave: 认领 Slice B — CAF 写回 executor_run 后 caf_memory.push"
```

### 2.2 自己发现的新缺口

如果你在开发中发现了**主机没列的新 bug/缺口**，可以自行提 fix/* 分支，但必须：
1. 在 commit message 里写明"自发现：[描述]"
2. 在 PR 描述里写明"主机账本 bug_id：BUG-xxx（如账本里没有，就说'新发现，主机请确认是否入账'）"

---

## 3. 每个功能缺口的开发闭环（6 步，少一步打回）

### Step 1 · 起分支 + 定边界

```bash
git fetch upstream main
git checkout -b feature/<slug> upstream/main
```

**你必须先写一份 `docs/design-<slug>.md`**（20-50 行足够），包含：
- 目标（一句话）
- 要改哪些文件（精确路径，不要 `src/**` 这种通配符）
- 不改哪些文件（边界）
- 四态覆盖表（cl1/cl2/cl3/cl4/cl5/cl6/cl7 是否全要）
- 验收标准（可被 `moon test` 或输出验证的）

commit 这份设计文档，才能开始写代码。

### Step 2 · 写代码

**核心原则：四态对齐 + 纯计算优先 + 增量零回归**

- 新功能先写**纯计算函数**（无状态、无 IO、可单测），再包进 MCP 工具
- 现有代码改函数签名 = **零回归改动**，新增参数必须有合理默认值、返回值形状零变化
- 新测试文件必须是 `_wbtest.mbt`（白盒，测试内部函数）或 `_test.mbt`（黑盒，测试公开 API）
- **不要手改** plugins/、.mbti、dist/、memory/bugs.md 的抬头状态

### Step 3 · 本地验证（强制四连）

```bash
# 1. moon fmt（改动文件 + 全仓各跑一次）
moon fmt
moon fmt --check   # exit 0 才继续

# 2. moon check（零 errors）
moon check src/改动的包

# 3. moon test --target js 全量（不要只跑子包）
moon test --target js
# 必须 Total tests: N, passed: N, failed: 0.

# 4. moon info + 再 fmt（同步 .mbti 后再跑一次格式化）
moon info
moon fmt
moon fmt --check
```

**任何一步失败 → 回到 Step 2 改**。不要跳过 fmt 直接 commit，CI 会红。

### Step 4 · Commit（强制 message 格式）

```
<type>(<scope>): <简短描述>

[可选] 原因 / 账本 bug_id / 关联设计文档

<type> = feat | fix | guard | refactor | docs | misc
<scope> = engine | store | router | server | ops | display | ... （改哪个包）
<简短描述> = 不超过 50 字符，中文英文均可

示例:
  feat(server): mcp_config_scaffold 工具（cl1）
  fix(engine): dag_cost_route 负载感知 tiebreak（BUG-336）
  guard(ci): check_skill_inject 守卫判据立项
  refactor(router): 多免费池 config_json 字段扩展
```

**一个分支一个 commit**（除非实在太长可以分，但每个 commit 必须**各自通过四连**）。

### Step 5 · Push 到你的 fork

```bash
git push origin feature/<slug>
```

### Step 6 · 提 PR（强制 PR 描述模板）

```
## 功能/缺口: <slug>

**主机账本 bug_id**: BUG-xxx（如账本里没有则写"新发现"）
**主机 plan 文档**: docs/improvement-plan-20261010.md §P0-b 或 docs/plan-light-worktree-isolation.md L158

### 改了什么
- src/server/model_router_ops.mbt: executor_run 成功后 caf_memory.push 回写
- src/router/model_router_caf.mbt: caf_memory.push 返回写入条数
- src/server/model_router_ops_wbtest.mbt: caf_dr_6 bad-JSON 降级锁（新增 1 条白盒测）
- docs/design-caf-writeback.md: 设计文档（32 行）

### 四态覆盖
| cl | 覆盖 | 状态 |
|---|---|---|
| cl1 MCP 工具存在 | model_route 新增 dry_run 分支回写 | ✅ |
| cl2 CLI 封装 | 不需要改（现有 fist.py call 可路由） | ⏭ |
| cl3 skill 文档 | 不需要（CAF 已有 router-caf-learning-plan.md） | ⏭ |
| cl4 测试 | caf_dr_6 白盒锁 | ✅ 新增 1 条 |
| cl5 L4 证据 | 见下方验证输出 | ✅ |
| cl6 文档同步 | AGENTS.md +1 工具 → 同步 | ✅ 待主机合入后 gen_plugins 自动同步 |
| cl7 插件投影 | 本机已手动 gen_plugins.py → 逐字节 diff PASS | ✅ |

### 验证输出
```
$ moon fmt --check
exit 0

$ moon check src/server
0 errors

$ moon test --target js
Total tests: 1747, passed: 1747, failed: 0.
（主机基线 1346 + 401 新增 = 1747，或主机基线没变 + 我的改动零新增 = 1346 保持）

$ python scripts/check_plugin_sync.py
PASS: 170 tools, version 0.3.9
```

### 边界声明（必须写）
- 未改 plugins/、.mbti、dist/、memory/bugs.md 抬头状态
- 未手改任何白盒锁行（caf_dr_6 是新增，不是修改已有）
- 未 push 到 upstream（主仓）
- 未用 HEAD 之后的并发 WIP 上下文（全部从 cd6a363 起分支）

### 后续
主机 MR 前会跑 moon fmt --check + moon test --target js 全量 + check_plugin_sync.py。如果任何一项红了，主机打回本 PR。
```

---

## 4. 主机打回时怎么改

主机提 review comment 打回你的 PR 后：

```bash
git fetch upstream
git checkout feature/<slug>
# 改代码...
moon fmt --check
moon test --target js
git commit -m "fix: 主机 review 意见：<简述>"
git push origin feature/<slug>
# PR 自动更新，不需重新提
```

**主机说"改得不好"，改；主机说"设计有问题"，重写 Step 1 的 design 文档再改。不要硬顶 review。**

---

## 5. 副机优先缺口清单（从 docs/2026-10-20-slave-tasks.md 自动同步）

每次开始前**必须**拉取主机最新的 `docs/2026-10-20-slave-tasks.md`：

```bash
git fetch upstream
git show upstream/main:docs/2026-10-20-slave-tasks.md | less
```

---

## 6. 常见坑速查

| 症状 | 原因 | 解决 |
|---|---|---|
| `Lexing error: unrecognized character "@" (U+0040)` | moon 版本不对。`@(expr)` 是 moon 0.1.20261016 新语法，0.1.20260920 及更早无法解析 | 确认 `moon --version` = 0.1.20261016，精确匹配 |
| `moon test` exit 0 但 `Total tests: N, passed: N, failed: 0.` 不是汇总行 | 不看 exit 码，只看汇总行（BUG-142：测试可执行 SIGABRT 时 `moon test` 仍回 exit 0） | 判绿只看汇总行，exit 0 只是必要条件 |
| `node:sqlite` 报 `returnArrays undefined` | Node 版本太低（<24） | 升级 Node ≥ 24 |
| `check_plugin_sync.py` 红（实测工具数 ≠ 插件 SKILL.md 里 tools= 数） | 你新增了 MCP 工具但没跑 `scripts/gen_plugins.py` | 跑完再 commit，逐字节 diff PASS 才能提 |
| `gen_plugins.py` 产出红账本（memory/bugs.md 抬头有 OPEN 但小记没 FIXED） | 账本状态要改就走 `bug_fix` 工具，不要直接改 Markdown | 查 `memory/bugs.md` 抬头状态 |
| CI `moon fmt --check` 红（说第 N 行格式不对） | 你跳过了本地 fmt | `moon fmt && moon fmt --check` 再 commit |
| PR 被主机打回说"基线不一致" | 你从 HEAD 之后的并发 WIP 起了分支 | `git fetch upstream && git reset --hard upstream/main` 然后 `git checkout -b feature/<slug>` |
| 改了 src/engine/xxx.mbt 又改了 src/server/server.mbt | 你在跨包改，scope 太大 | 拆成两个分支：fix/engine-xxx + fix/server-yyy，各提各的 PR |
| moon 版本 0.1.20261016 下载不了 | moon 官方 nightly 有临时不可用的时候 | 等一会儿再试；或用 CDN mirror（国内可选腾讯云 COS） |

---

## 7. 你能做什么 · 不能做什么

### ✅ 能做
- 新功能：纯新增模块、新 MCP 工具、新 CLI 子命令、新 skill 文档
- Bug 修复：账本里 OPEN 的 bug，或你自己发现的 bug
- 守卫族：新增 CI 判据脚本（`scripts/check_*.py`）
- 重构：不改变语义的结构优化
- 文档：README、AGENTS、docs/ 下任何文档
- 黑盒测试：新增 e2e 脚本在 `scripts/blackbox/`

### ❌ 不能做
- 直接 push 到 upstream（主仓）或主仓的 main/master 分支
- 手改 plugins/ 四宿主目录（gen_plugins.py 会覆盖）
- 手改 memory/bugs.md 的抬头状态（用 bug_fix/bug_mark_status 工具改）
- 用 HEAD commit 之后的并发 WIP 上下文开发（所有分支从 cd6a363 起）
- 跳过 moon fmt / moon check / moon test 全量四连
- 在一个分支里混多个 scope（同时改 engine + server + store = 自动打回）
- 超过 50 个文件改动（scope 太大，拆 PR）

---

## 8. 你是谁 · 主机是谁

- **你（副机）**：自主迭代 FIST-Mbt 功能缺口的 Agent，每个缺口独立分支独立 PR。你的代码**不会**自动合入主仓，只有主机 MR 审核后才会。
- **主机**：维护主仓 default 分支的 Owner，唯一能动主仓的实体，MR 审核人，账本守门人，插件投影机。主机可能在改并发 WIP（本机 195 行 M），但你看不到——你从 HEAD commit 起分支就对了。

---

**最后一条**：主机不是你的阻塞——你自己认领缺口、自己分支、自己闭环、自己提 PR。主机 MR 前跑四连自动判绿，红了打回，绿了合入。**你提的每个 PR 都是主机的候选合入项，主机 MR 后跑一次 gen_plugins.py + check_plugin_sync.py 统一收口。**

有问题吗？没有的话，按 §0.2 setup → §2 认领缺口 → §3 闭环 → §5 提 PR。祝好运。
