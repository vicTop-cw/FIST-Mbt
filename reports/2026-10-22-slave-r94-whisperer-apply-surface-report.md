# 2026-10-22 · 副机 R94 追记三 · `whisperer_patrol.py --apply` 快进面收口

分支：`slave/integrate/r93-on-cef1e9c-r94`（基点 gitcode/main `cef1e9c`）
交付物：`scripts/whisperer_patrol.py` + `scripts/README.md` + `memory/2026-10-22.md`（纯 Python/文档面，零 `.mbt` 改动）

## 结果摘要

上一轮交付时我自己写明「`--apply` 的 ff-only 面本轮未实测，属未验证面，不得据自述宣称可用」。
本轮把这一格补成实测面，并顺手抓到两条真缺陷：

1. **`ff_merge` 的落点错**（实害级）：旧实现里 `git merge --ff-only <候选分支>` 合的是**当下签出的分支**，
   不是 base——在 feature 分支上跑 `--apply`，被快进的是那条 feature 分支自己；非零 rc 全被吞
   （合没合上都不吭声）；每轮还空转一次 `git checkout cur`。
   现在 [scripts/whisperer_patrol.py:97-124](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L97)
   有三道前置：工作树干净（`:106`）/ HEAD 就站在基线对应的本地分支上（`:108`）/ 逐条 `--ff-only`
   且第一条不合常理即停；`ff_merge` 回 `(merged, problems)`，被挡 ⇒ main 判 **rc=1**
   （[scripts/whisperer_patrol.py:366-386](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L366)）。
   刻意**不**做「自动 checkout 基线」：那是替人决定签出状态，越界（金条四）。
2. **`probe_branches` 漏传 `cwd`**：`git merge-base --is-ancestor` 是该函数里唯一没转发 `cwd` 的调用
   （修后 [scripts/whisperer_patrol.py:87](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L87)）。
   真仓里 cwd 恰等于仓库根 ⇒ 这一漏在真实跑法下不可见，只有沙箱自证面照得出来。是新增四格当场抓到的。
3. **docstring 旗名漂移**：模式清单四行全写 `python scripts/whisperer.py …`（R93 改址后没跟上）。
   这不是排版问题——`whisperer.py` 是主机编排真源，它的 Step 0 会 `reset --hard` + 强推两远端（TASK-018）；
   把 agent 的命令行指到那支脚本上去，等于给定时任务递刀。现已全部指回 `whisperer_patrol.py`
   （[scripts/whisperer_patrol.py:15-27](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L15)）。

自证面：`--selftest` 六格 → **十格**（新增 `--apply` 四格：基线上快进成功且 sha 前进 / 错签出整批不动 /
脏树整批不动 / 分叉分支永不进快进面，`:248-272`）。

## 资源消耗

- 本轮 21 个回合（配额 40），墙钟约 22 分钟。
- 子进程实测：`whisperer_patrol --selftest` ×3（六格→十格→修 cwd 后全绿）、变异副本 4 发、
  真仓 `--apply --scan-only --no-fetch` 1 发、`run_guards --selftest` ×2、全量电池 97 格 ×1、
  `moon build --target js` ×1（失败，见「遗留风险」）。
- 未动任何共享线：无 push（除本分支）、无 merge、无 force；沙箱动作全在 `tempfile.mkdtemp` 里。

## 任务分配记录

- 指挥官（我）：判定这一格属「已交付单元的未验证面」，亲自收口——不涉及拆解，单文件级；
  不派子代理（改的是我自己上一轮的交付面，转包反而丢上下文）。
- 风语者池（`docs/tasks/backlog/`）：本轮不新增任务——缺陷已当场修完；
  TASK-018/019/020/021/022/023 仍挂 `status: backlog` 等 owner 裁决，未代做。
- 变异对照由我在 `temp/mut-wsp/`（gitignore 面）落副本跑，跑完删除，不进出货面。

## 遗留风险

1. **本机 JS 构建仍红**：`moon build --target js` 报 `Error: Sys_error("\\\\?: Invalid argument")`
   ——moonc 的 `\\?\` 长路径 ICE（项目记忆在册）。连锁后果：全量电池 97 格里 **38 红**，
   成因都是「没有 `_build/js` 产物 / 没有 node 产物 / 缺 fpdf 模块 / 缺 temp 前置」这一族，
   不是本单元引入。逐条点名（`run_guards` 读数）：`check_release_asset_names` rc=1、
   `check_plugin_sync` rc=1、`gen_plugins --check` rc=1、`fist-gate --selftest` rc=2（G4 fmt 档
   `failed to execute git --no-pager diff` 退化）、`check_host_installable` rc=1（DSH manifest 0.3.9≠0.3.10）、
   `cli_flag_probe` rc=1、以及 demo/verify 族 rc=1（`task not found: T0r3` 等，需真 server + 产物）。
   按 owner 口径「预存红不代修，但必须点名 rc 与成因」处理。
2. **`check_bug_reference_integrity.py` rc=1**：main（`cef1e9c`）带进来的 J1 注释面悬空 17 条 > 上限 1。
   计数在我改动前后都是 **17**（本轮新增 0 条悬空引用），已入池 TASK-023 待裁决，不代修。
3. **共享工作树里有别人的在飞改动**：提交前 `git status` 出现 `src/router/router_state.mbt`（+1）与
   `src/router/model_router_wbtest.mbt`（+17），形状是 `use_caf_memory: false` **重复插入**
   （同一 record 字面量里两个同名字段，直接编译红）。不是本单元产物（本轮零 `.mbt` 改动），
   疑似并行 agent 在飞——**我没有提交、也没有还原**它们；本次提交只显式 stage 三个文件。
   这一格需要 owner 认领：如果是别的 agent 的半成品，重复字段会让 `moon test` 红在无辜的分支上。

## 后续建议

1. `--apply` 若要「自动 checkout 基线再快进」，得先有裁决：定时脚本改签出状态是否可接受（本案选了拒绝）。
2. 电池面建议加一格「`ff_merge` 必须带回执元组」的判据——但更稳的是现在这四格沙箱自证，不建议再加尺。
3. `run_guards` 里那 38 红可以在 CI（有产物）与本机（无产物）之间分档：本机的「缺前置」应像
   SKIP 那样单列一类「工具链不给量」，否则每次读电池都要人肉分诊一遍。
4. 给共享工作树立一条纪律：并行 agent 改 `.mbt` 前先 `reserve_scope`，避免「谁的半成品在我分支上红」。

## 超额内容

- 修了本单元范围外的两处：`probe_branches` 的 `cwd` 漏传、模块 docstring 的旗名漂移（后者是
  TASK-019「双活定址」的尾巴，R93 改址时漏了 docstring）。
- 变异对照 4 发是自查要求之外的动作，用来证明新格不是装饰；副本用完即删。
- 未做：TASK-008（scripts 命名收口，39~40 支待定名）——体量是 `git mv` ×50 + CI/README/docs 全改，
  且与四支同伴分支在 `scripts/README.md` 上必撞，等 TASK-022 合序裁决后再动。

## 来源

- 真源改动：[scripts/whisperer_patrol.py:87](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L87)、
  [:97-124](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L97)、
  [:226-272](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L226)、
  [:366-386](file:///F:/AI/Fist-Mbt/scripts/whisperer_patrol.py#L366)
- 登记面：[scripts/README.md](file:///F:/AI/Fist-Mbt/scripts/README.md)（`whisperer_patrol.py` 条目：
  三道前置 + rc 契约新增一档 + 十格清单，`--selftest` 计数按实现现读）
- 实测读数：本文件「结果摘要」「遗留风险」两节的每条 rc 都是本轮命令回执，非自述（金条八）
- 上游依据：TASK-009（风语者探测/入池引擎）、TASK-018（编排真源的破坏性 Step 0）、
  TASK-019（whisperer 双活最终形状）、TASK-023（J1 17 条悬空）
