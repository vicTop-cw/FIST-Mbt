# D·polish：`plugins/` 四宿主 cl7 插件态对齐

> **模式**：polish（打磨完善，`forbid_new_features`；禁用 `publish` / `publish_parallel` / `dag_publish`）
> **任务**：task-20 · **板块**：`plugins/` cl7 一源四态第四态
> **日期**：2026-10-24 · **执行者**：audit-preservation（从审计者转打磨者）
> **作业面**：主仓，不开 worktree
> **入库**：`e0912f96`（9 文件重投影）

---

## 一、结论

**cl7 判据从 FAIL 修到 PASS，根因是 A 类（真源改了没重投影），不是手改、不是判据过时。**

| 项 | 修前 | 修后 |
|---|---|---|
| `check_plugin_sync.py` | **FAIL**：9 个文件与真源投影不一致 | **PASS**：4 宿主 / 64 生成文件 / 170 工具 / v0.3.10 |
| `gen_plugins.py --check` | FAIL | OK |
| `check_tools_sync.py` | — | PASS（170 工具） |
| `check_doc_surface.py` | — | PASS（170 工具逐个可查、分组和=170） |
| `check_badge.py` | — | PASS（1455/1455） |

**改动量：9 文件 / +17 −17 行，零新功能。** 全部是同一个账本摘要字符串的刷新。

---

## 二、证据

### 2.1 修前：9 个漂移文件（完整清单）

`python scripts/gen_plugins.py --check`：

```
FAIL 插件态漂移（9 个文件与真源投影不一致）：
  - README.md：内容不一致
  - atomcode\skills\fist-commander\SKILL.md：内容不一致
  - atomcode\skills\fist-mbt\SKILL.md：内容不一致
  - claude\skills\fist-commander\SKILL.md：内容不一致
  - claude\skills\fist-mbt\SKILL.md：内容不一致
  - codearts\skills\fist-commander\SKILL.md：内容不一致
  - codearts\skills\fist-mbt\SKILL.md：内容不一致
  - deepseek-harness\instructions.append.md：内容不一致
  - deepseek-harness\skills\fist-mbt\SKILL.md：内容不一致
  真源解析：mcpServers=.mcp.dev.json（候选 .mcp.dev.json, .mcp.json）
```

### 2.2 根因定位：唯一的真源变动是 `memory/bugs.md`

`gen_plugins.py` 的真源输入含账本（`:14` 声明、`:57` 读文件、`:255` 解析、`:436` 注入摘要）：

```
# 各真源面自上次重投影（6d3a851c）以后的提交数
plugins/source/server.mbt   0 笔
moon.mod                    0 笔
.mcp.dev.json               0 笔
src/server/server.mbt       0 笔
memory/bugs.md              1 笔   ← 唯一变动
```

那一笔是 `0f63b055 feat(guard): 两把新判据 —— 产物可运行性（17 格）+ worktree 卫生（43 格）`，
它在 `memory/bugs.md` 落了 1 条新 BUG 条目：

```
memory/bugs.md | 8 +
```

⇒ 账本抬头状态计数从 `388 条 / 25 待修` 变为 `389 条 / 26 待修`，
**而 `plugins/` 没有随之重投影** ⇒ 9 个含该摘要的生成文件全部与投影不一致。

### 2.3 改动内容：纯字符串刷新（证明零新功能）

`git diff` 抽样（三宿主 + README，其余 6 个同型）：

```diff
-description: … avoid known pitfalls (bug ledger: BUG-1~405 共 388 条入账：25 条待修 / 343 条已修 / …)
+description: … avoid known pitfalls (bug ledger: BUG-1~406 共 389 条入账：26 条待修 / 343 条已修 / …)

-     ledger=BUG-1~405 共 388 条入账：25 条待修 / 343 条已修 / …
+     ledger=BUG-1~406 共 389 条入账：26 条待修 / 343 条已修 / …

-## Known issues ledger (BUG-1~405 共 388 条入账：25 条待修 / …
+## Known issues ledger (BUG-1~406 共 389 条入账：26 条待修 / …
```

**无工具增删、无参数变化、无文案改写。** 这是 polish 模式下允许的正当动作（重跑生成器）。

### 2.4 修后复跑

```
$ python scripts/check_plugin_sync.py
PASS 插件态一致：4 宿主 / 64 个生成文件 / 170 工具 / v0.3.10 / 启动参数真源 .mcp.dev.json

$ python scripts/gen_plugins.py --check
OK 插件态与真源一致（170 工具 / v0.3.10）｜启动参数真源取到 .mcp.dev.json
```

---

## 三、分析

### 3.1 四宿主一致性细查：**结构差异是设计意图，不是缺陷**

`ls plugins/<host>/` 初看四宿主不齐（只有 `claude` 有 `.mcp.json` 和 `.claude-plugin/`），
但对照生成器头部规格（`gen_plugins.py:18-22`，逐字引用）：

```
产出（宿主顺序 = 指定顺序：atomcode → codearts → deepseek-harness → claude）：
  plugins/atomcode/skills/{fist-mbt,fist-commander}/
  plugins/codearts/skills/{fist-mbt,fist-commander}/ + UserSkillStatus.append.txt
  plugins/deepseek-harness/skills/fist-mbt/ + instructions.append.md
  plugins/claude/{.claude-plugin/plugin.json,.claude-plugin/marketplace.json,.mcp.json,skills/fist-mbt/}
```

**实盘逐宿主核对，全部命中规格**：

| 宿主 | 生成文件数 | 特征件（规格要求） | 符合 |
|---|---|---|---|
| `atomcode` | 15 | `INSTALL.md` + `assets/` + 双 skill + 9 份 references | ✅ |
| `codearts` | 16 | 同上 + `UserSkillStatus.append.txt` | ✅ |
| `deepseek-harness` | 14 | `instructions.append.md` + **单** skill（`fist-mbt`，无 `fist-commander`） | ✅ |
| `claude` | 18 | `.claude-plugin/{plugin.json,marketplace.json}` + `.mcp.json` + 双 skill | ✅ |

> **结论：「四件齐 = manifest / .mcp.json / skills / instructions」这个尺对四宿主并不成立。**
> 四宿主的宿主机制不同（Claude 有插件清单机制，DeepSeek Harness 用 instructions 追加，CodeArts 有技能状态文件），
> **生成器规格就是权威面**，拿统一四件套去量会得出 9 个假缺件。
> 这是我在审计面踩过的同型错误的镜像（判例-8：拿「我以为的标准」当尺）。

### 3.2 禁用工具的「声明 vs 实现」：**声明真实，且无执行点是账本已诚实登记的**

`mode_list` 里 polish 禁用 `publish` / `publish_parallel` / `dag_publish`。实测：

```
$ git grep -n 'forbidden_tools' -- src/
src/ops/ops_modes.mbt:193    /// forbidden_tools（某些 mode 显式禁用的工具/任务名；空数组表示无约束）。
src/ops/ops_modes.mbt:194    fn mode_forbidden_tools(mode_str : String) -> Array[String] {
src/ops/ops_modes.mbt:199      "polish" => ["publish", "publish_parallel", "dag_publish"]
src/ops/ops_modes.mbt:242-245  （拼进 mode_list 的 JSON 回执）
src/ops/ops_modes_wbtest.mbt   白盒锁
src/server/server.mbt:3549      （仅 mode_list 的 description 文案）
```

**⇒ 三个工具名真实存在（`check_tools_sync` 判据 4 已锁「名单 ⊆ 真注册集」），
但本仓内没有自动化拦截点。**

**这是否是缺陷？不是未登记的缺陷。** `memory/bugs.md` 的 BUG-37 FIXED 段**已诚实标注**：

> `mode_forbidden_tools` 换成真实注册名 `publish / publish_parallel / dag_publish`（src/ops/ops_modes.mbt），
> 并把同一臆造名从 polish/tidy/verify 三份模板里一并清掉（文档面同源）。
> **诚实标注：本仓内没有自动拦截点，该名单是给调用方/指挥官匹配用的机器面**，名字不存在时红线才真正空转。

**所以「polish 禁用 publish」的正确读法是：这是一条给调用方/指挥官读的机器可读约束，不是服务端硬门。**
若要让它在服务端**真咬**，那是**新增执行点（= 新功能）**，超出 polish 授权面。
**本项只做声明面核对，不开新功能。** 建议另立 advance 任务。

> **顺带修正一处题设偏差**：统帅任务书 §④ 写「查这 3 个工具在 `src/ops/ops_modes.mbt` 里**是否真被禁**」。
> 准确说法应是「**名单是否真实**（是，已被 check_tools_sync 锁）+ **是否有执行点**（本仓无，账本已登记）」。
> 这两件事必须分开问——混为一谈会得出「polish 的禁用在骗人」的错误结论。

### 3.3 「生成器 vs 手改」护栏：**已存在且已验证有效，不需要新增**

`check_plugin_sync.py` 现有 7 道检查：

| 判据 | 内容 |
|---|---|
| **J1** | 漂移：**子进程跑 `gen_plugins.py --check`**，同一逻辑两份实现互相制衡 |
| J2 | 四宿主齐全且非空 |
| J3 | 无残留 `{{占位符}}` |
| J4 | claude manifest 自述版本 == `moon.mod` |
| J5 | 启动参数单一真源（`plugins/claude/.mcp.json` 与根 `.mcp.dev.json` **逐字相等**） |
| J6 | 每个 SKILL.md 的 stamp 计数 == 实测 |
| J7 | 反幻影：解析退化时绝不给绿灯 |

**变异测试（本轮实做，验证 J1 真能红）**：

```
# 手工往 plugins/claude/skills/fist-mbt/SKILL.md 追加 2 行
$ python scripts/check_plugin_sync.py
FAIL 插件态（一源四态 cl7）不一致：
  - J1 插件态漂移：gen_plugins.py --check 退出码 1（FAIL 插件态漂移（1 个文件与真源投影不一致）：）
  -         - claude\skills\fist-mbt\SKILL.md：内容不一致
# 恢复后立即 PASS
```

⇒ **「四宿主目录必须与生成器投影一致」这条护栏已经由 J1 完整覆盖。
本轮不新增判据（tidy/polish 的 `forbid_new_code` / `forbid_new_features` 也要求如此）。**

---

## 四、缺口与风险

### 4.1 本轮触发方式的一个瑕疵（自曝）

`gen_plugins.py` **没有 `--help`**——我按任务书 `python scripts/gen_plugins.py --help` 探查时，
它**直接执行了生成并写盘**（输出 `OK 已生成四宿主插件态…`）。

- **影响**：实际效果与预期一致（就是要重投影），**未造成损坏**；
- **风险**：一个可写盘的工具对未知参数不做拒绝，等于「摸一下就改」。
  按本仓自己的判例-10c 口径，这是「**工具的行为面没有与调用面契约对齐**」。
- **处置**：本轮不改（polish 不加新功能）；**建议另立**：`gen_plugins.py` 对未知参数应拒（rc=2）并支持 `--help`。
- **留给后续的证据**：`python scripts/gen_plugins.py --help` → 输出是生成结果而非用法。

### 4.2 cl7 红灯会周期性复发（结构性）

本次红灯的**触发源是账本条目数变化**——每新增一条 BUG，账本摘要就变，9 个生成文件就会漂。
⇒ **这不是偶发事故，而是「高频变动的真源」驱动「低频重投影」的固有滞后**。

**缓解建议（非本轮范围）**：把 `gen_plugins.py` 接进 pre-commit 或 CI 的自动修复位
（`run_guards` 已有 cl7 判据当门，但门只报红不自修）。
另一条更彻底的路：让 SKILL.md 不含账本计数（改为引用 `memory/bugs.md`），
从根上去掉这个高频漂移源——**但那是改真源内容，属结构决策，需 owner 裁决**。

### 4.3 未覆盖

- 四宿主**未在真实宿主内装载验证**（`AI-DEVELOPMENT-STANDARD.md` §7 已知边界：
  「cl7 只保证『等于投影』，不保证『宿主可用』」）。本轮同样不覆盖。
- `plugins/source/references/` 的 9 份 reference 正文语义一致性**未审计**（本轮只验投影一致）。

---

## 五、复现命令

```bash
# 诊断
python scripts/check_plugin_sync.py            # 修前 FAIL（9 漂移）→ 修后 PASS
python scripts/gen_plugins.py --check          # 只报不写，rc=1 即漂移

# 重投影（唯一允许的改 plugins/ 的方式）
python scripts/gen_plugins.py

# 根因取证
git log --oneline 6d3a851c..HEAD -- memory/bugs.md plugins/source/server.mbt moon.mod .mcp.dev.json src/server/server.mbt

# 四宿主结构 vs 生成器规格
find plugins/<host> -type f | sort

# 禁用工具声明面
git grep -n 'forbidden_tools' -- src/
grep -n -A6 '^## BUG-37 ' memory/bugs.md      # 账本里的诚实标注

# 相关门禁
python scripts/check_tools_sync.py
python scripts/check_doc_surface.py
python scripts/check_badge.py temp/pt27.log README.md
```

---

## 六、来源

| 角色 | 贡献 |
|---|---|
| 统帅 | 板块划分、cl7 rc=1 的历史线索、「禁加新功能」纪律、判例-10c / 11 |
| `memory/bugs.md` BUG-37 | `forbidden_tools` 无执行点的诚实标注（本轮据此避免误判为缺陷） |
| `scripts/gen_plugins.py:18-22` | 四宿主产出规格（本轮据此判定结构差异是设计意图） |
| `reports/2026-10-24-merge-precedents.md` 判例-8 | 「拿我以为的标准当尺」的镜像教训 |
| 本审计组 | 根因定位（bugs.md 是唯一变动真源）、变异测试验证 J1 护栏、题设两处偏差澄清 |
