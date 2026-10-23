# 2026-10-23 · R141 工具链地板单一真源 + `check_doc_surface` J17 · 交付报告

分支：`slave/gate/toolchain-floor-guard-r141`（基点 `gitcode/master 788c5823`）
性质：判据扩展（治理面）+ 文档一致性修复 —— 主机清单「对账后仍缺的一面」#4 的落地单

---

## 结果摘要

- **立真源**：新增根级 `toolchain.json`，把「MoonBit 工具链地板」与「Node 地板」从散文里取出来，第一次有了机器可读的唯一出处（含 `why_*` 与 `how_to_bump` 两条操作说明，以及一句「与 moon.mod 的 version 是两个东西，别混判」的防混淆注记）。
- **立尺**：`scripts/check_doc_surface.py` 新增 **J17 工具链地板 ↔ `toolchain.json` 对表**，四个方向：
  1. 现状规范表面（跟踪面 `.md`，排除历史面与生成副本）里每条地板声明必须 == pin —— 三种写法都认：`≥ x.y.z` 式、`badge/MoonBit-x.y.z` 徽章式、`x.y.z 精确` 钉版式（副机 playbook 用的就是最后这种）；
  2. 必须声明地板的四个面（README / README_EN / USAGE / AGENTS）把地板删光 ⇒ 红（「删正身消解违例」不是修法，口径同 J4 的「权威被删空必红」）；
  3. CI 的 `node-version` 也必须 == pin ⇒ 「文档教的环境」与「CI 实际跑的环境」第一次被绑在一起；
  4. 三档自拒：读不到 `toolchain.json` / 枚举不到 `.md` / 一个地板都解析不到 ⇒ FATAL，绝不拿「没读到」当绿灯。
  豁免面：`「…」`/`『…』` 之内的转述（副机清单 POLISH-04 那一行正是这个形状）、`reports/` `memory/` `docs/archive/` CHANGELOG BACKLOG 历史面、`plugins/<host>/` 生成副本（cl7 逐字节比真源）。
- **尺上岗第一跑就抓到一条真红**（不是自设的假想违例）：`docs/2026-10-12-mcpcf-embed-serve.md:52` 写「要求 Node >= 22.5」，而 README「环境要求」与 CI 的 `node-version: '24'` 是 24 —— 与主机清单 POLISH-04 记的「README 教 0.1.20260827、代码要 0.1.20261016」是**同一个形状在另一面复发**。已按真源改字并写明取 24 的理由（`node:sqlite` 22.5 就有，但本仓用的是 `returnArrays`，<24 退化为对象行）。
- **声明面同步**（J10 自己抓的，不是我主动想起的）：第一跑 J10 就红了 `AGENTS.md:439` / `AI-DEVELOPMENT-STANDARD.md:15` / `templates/pipeline_mode_tidy.md:45` 三处「J1-J16 < 实现最高 J17 —— 声明滞后」。三处已同步到 J1-J17 并补 J17 的分工说明与自检清单。

## 证据（L4：命令实回）

| 判据 | 修前 | 修后 |
|---|---|---|
| `python scripts/check_doc_surface.py` | FAIL 4 条（J10×3 声明滞后 + J17×1 真红 Node 22.5） | **PASS**（170 工具 / moon.mod 0.3.10 / J17 已进 PASS 行） |
| `python scripts/check_doc_surface.py --selftest` | — | **SELFTEST OK**，规则反解含 `J17`；J17 十一支断言（其中「豁免不误红」是一支三参数的循环 ⇒ 实际执行 13 格：干净面不误红、落后必红、徽章漂移必红、`精确` 式漂移必红、引文不误红、历史面不误红、生成副本不误红、地板删光必红、CI `node-version` 漂移必红、无 pin 必自拒、枚举空必自拒、解析不出必自拒、真实现状面不误红） |
| 真红样本 | `docs/2026-10-12-mcpcf-embed-serve.md:52` 声明 node 地板「22.5」!= 真源 24 | 该行按真源改为 ≥ 24 并写明理由；复跑 J17 无违例 |
| 电池（权威交付门） | — | **75 格 / 失败 9 / SKIP 5 / 缺执行面 0**，逐格见下节「电池终读」 |

红前红后都取的是同一条命令的实际退出码与打印行，不是自述。J17 的合成违例由 `--selftest` 自己考，`SELFTEST OK` 那行的判据清单从自检正文反解（不手写计数）。

## 电池终读（`python scripts/run_guards.py`，本机 2026-10-23 11:59 起跑）

**格数 75（手写 75 + 自动 0）/ 失败 9 / SKIP 5 / 缺执行面 0。** 本单没新增格、没新增 CI 步，所以格数与 R136 收口时同面。

9 条失败逐条定性（谁的红）：

| 尺 | rc | 归属 |
|---|---|---|
| `check_publish_payload.py` | 1 | **本单的扫描时刻竞态，不是缺陷**：电池 11:59:51 起跑，我的提交 12:02:10 才把 `toolchain.json` 落进跟踪面，于是它报「未被 .gitignore 挡住又没被 git 跟踪 ⇒ 会随包公开」。提交后单跑同一条尺 = **PASS 发布载荷面干净：将随包公开 1329 件，其中未被 git 跟踪的 0 件** |
| `check_slave_task_list.py` | 1 | 预存红：D1 文首自述「失配 0」而尺实算 20 条（主机清单面，R138 车道） |
| `check_scripts_index.py` | 1 | 预存红：`tmp_merge_batch.sh` 未登记 |
| `check_doc_dup.py` | 1 | 预存红：`scripts/README.md` 冗余块（R136/R138 车道） |
| `whisperer.py --selftest` | TIMEOUT(600s) | 预存红：尺自己超时，非本单面 |
| `check_unit_number_unique.py` | 1 | 预存红：轮次号撞号基线（本单取号前已查三面，R141 未与既有报告同号） |
| `check_unit_number_unique.py --selftest` | 1 | 同一族的自检红，随上面一起，不重复计债 |
| `check_battery_count_doc.py` | 1 | 预存红：X5 门禁尺登记 60 / 现读 63（别人加尺没同步锚点） |
| `check_selftest_inventory_doc.py` | 2 | 预存红：X4 两处自述失联（其一正是上面那条 `--selftest` 红导致的连锁） |

⇒ **本单交付面上没有新增红**；`check_doc_surface`（含 J17）与 `check_plugin_sync`/`check_tools_sync` 等在电池里为 PASS。SKIP 5 条都是「缺前置 temp 产物」那类历史格，不构成任何一格的证据。

## 资源消耗

- 工具调用：约 20 次（读代码 / grep / 4 次 Edit / 3 次守卫跑 / 1 次建分支）。无 LLM 子代理参与判定；网络调用 0 次（`git fetch` 除外）。
- 时间：本机约 25 分钟；电池为唯一长任务。
- 改动量：5 个文件修改 + 1 个新增，代码面 `+209` 行（其中 J17 实现 ~140 行、自检 ~60 行、文档注释 ~9 行），文档面 4 行级修改。
- 新增 CI 时间：**0**（J17 挂在既有的 `check_doc_surface` 步骤里，`--selftest` + 全量 CI 早就各跑一次，不新增格、不新增步、不动 `BATTERY-REGISTRATION` 锚点 ⇒ 不触发 R136/R138 那种「锚点整体位移」返工）。

## 任务分配记录

- 按金条四，本单没有派给子代理**写码**：判据的自检格设计要逐条对着既有约定（反解计数、三档自拒、反向对照齐配），委派的重做成本高于自查。
- 委派出去的是**取证**：1 个 Explore 子代理负责「工具链地板在全仓有哪些真源候选」，回传 5 问的实读证据（`moon.mod` 无兼容性字段 / 全仓无机器可读 pin / CI 装 `latest` 不钉版 / Node 倒是钉了 `'24'` / `check_badge.py` 与 `moon_version()` 都不碰工具链版本）。该回传的两处结论被我自己复核推翻或修正过一次（见「超额内容」），已以现读为准。

## 遗留风险

1. **预存红（本单未触碰面，按 expected 登记，不代修）**：`check_doc_dup.py` rc=1（`scripts/README.md` 仍 232 块冗余 —— 主线 `b954eaf0` 那次手工合并只搬了尺/CI/报告，没搬被检文件；R138 分支 `ca1a324f` 才是重写版）、`check_scripts_index.py` rc=1（若干脚本未登记）、`check_selftest_inventory_doc.py` rc=2（X4：`check_battery_count_doc` / `check_unit_number_unique` 的 `--selftest` 本身红）。这三族在 R138 报告里已逐条点名，本单不重复登记、不代修。
2. **J10 的声明面不含 `scripts/README.md`**，而那里 8 个重复块都写着「J1~J16 档」—— 本单的 J17 一进去，那句话就成了新的声明滞后，却没有任何尺看得见（J10 只扫 AGENTS / 规范正文 / templates / plugins/source）。没有顺手改它，是因为那份文件正被 R138 整体重写，改 8 个重复块既是 churn 又必撞车。建议 R138 并线后把 `scripts/README.md` 纳入 J10 声明面。
3. **J17 只保证「文档说的 == pin」，不保证「pin == 代码真正需要的版本」**。地板的语义真源仍靠 `is` 模式匹配这类事实写在 `why_moonbit` 里；CI 装的是 `latest`（不钉版），所以「CI 上编不过」不会被本尺抓住 —— 那是另一族问题（BUG-118 / fmt 世代那族同源）。
4. `toolchain.json` 是新的根级跟踪文件，`moon publish` 打包面（工作树 − .gitignore）会带上它；`check_publish_payload` 的凭据形状扫描对它无感（无 key 形状字段），已核。

## 后续建议

1. 主机并线后跑一次 `check_doc_surface.py --selftest` + 全量（CI 已含），确认 J17 在 Linux 侧对 `docs/*.md` 的枚举与本机一致（CRLF / 编码差异会改变行号但不改变判定，已用 `errors="replace"` 兜住）。
2. 把 `docs/2026-10-20-slave-tasks.md` 里 POLISH-04 的状态改判为 `已落地`、并在「对账后仍缺的一面 #4」标注「已由 R141 关闭」—— 本单刻意没动那份清单：它同时是 R138 分支的主战场，且清单锚点由 `check_slave_task_list.py` 现算，跨分支并改会造出第二个「位移 10 处锚点」的返工。
3. 下一族同形状缺口：`moon.pkg` / `.github` 里 `latest` 与本地钉版的关系没有尺；若要治，应显式裁决「CI 是否钉版」而不是让尺猜。

## 超额内容（本单范围之外顺手做的）

- Explore 子代理回传里有一条「CI 的 Node 钉了 `'24'`」，我据此把 **CI `node-version` ↔ pin** 也纳入 J17（原任务只要求文档地板对表）—— 文档说的与 CI 跑的不一致，本就是同一族缺口。
- 复核中纠正了子代理两处读数：① 它称「`moon.mod.json` 未跟踪、无兼容性字段」，实际本仓根本没有 `moon.mod.json`（是 TOML 形态的 `moon.mod`，同样无该字段）；② 它把 `scripts/moon_env_probe.py` 列为版本真源候选，现读确认它只做 `MOONC_OVERRIDE` shim 发现与 spawn 普查，不读不校任何版本号 —— 两条都没有写进判据。

## 来源

- 主机任务清单：`docs/2026-10-20-slave-tasks.md`「对账后仍缺的一面」#4（版本地板无人认领，建议纳入文档面判据）与 POLISH-04 行
- 既有口径：`AI-DEVELOPMENT-STANDARD.md` §1 守卫族、J4「权威被删空必红」先例、J10 声明↔实现对表、J13/J14/J15 的「上岗即抓自家」传统
- 实测面：`python scripts/check_doc_surface.py{,--selftest}`、`python scripts/run_guards.py`（电池）、`python scripts/check_doc_dup.py` / `check_scripts_index.py` / `check_selftest_inventory_doc.py`（预存红定性）
