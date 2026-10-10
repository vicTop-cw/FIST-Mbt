# 2026-10-10 · BUG-140 / BUG-141 · asset 落库 → 跨进程回灌 → inject 检索 三态闭环

## 结果摘要

修复 `[asset]` 外部资产从「注册落库」到「重启后 inject 可检索」的两段缺口，均 FIXED，账本 `### FIXED(2026-10-10T06:58:44Z / BUG-140, BUG-141)` 已盖章。**证据梯 L4：白盒锁 + 跨进程探针都做到「修前红 / 修后绿」。**

## 资源消耗

- `moon check --target js src/server` 0 errors（825 warnings）；`moon build --target js` 0 errors（288 warnings）+ `patch_esm_main.py` 已跑。
- `moon test --target js src/server` **172 passed / 0 failed**（171 基线 + 1 新锁）。
- 权威稳定门槛 `moon test --target js` 全仓 = **623/623 通过 / 0 失败**。

## 任务分配记录

| 阶段 | 承担者 | 交付 |
|---|---|---|
| BUG-140 根因定位 + 落库修复 | 指挥官 + 子代理 d01079cd | `evolve_asset_register` 在 `Archive::add` 后同步调 `evolve_store.evolve_upsert(...)` |
| BUG-141 根因定位 + 回灌放宽 | 子代理 d01079cd | `sync_db_lessons` 过滤由 `[lesson]` 放宽为 `[lesson] \|\| [asset]` |
| BUG-141 白盒锁 | 子代理 d01079cd | `fist-mbt_wbtest.mbt:43-75` 新测试 |
| 跨进程 inject L4 探针 | 子代理 d01079cd | `temp/fix141_probe.py`，`CROSS_PROC_INJECT_HIT` 修前 False / 修后 True |
| 活库注册 8 条生态资产 + 备份 | 子代理 d01079cd | `temp/fist-mbt.db.backup-b141-3f648518/`，活库 `[asset]` 0→8 |

## 分析

- **BUG-140**：`evolve_asset_register` 只调 `@evolve.Archive::add`（内存态），从不写 `evolve_artifacts` 表 → 重启即失，且新起的进程完全看不到。修法：落库到 `evolve_store.evolve_upsert`，落点见 `src/server/server.mbt` L3208-3226。
- **BUG-141**：`sync_db_lessons` 是唯一 DB→内存 Archive 装载器，但过滤只认 `has_prefix("[lesson]")`，`[asset]` 永远不进内存 → 同一进程内注册可见，跨进程 inject 检索为空。`server.mbt` L646-648 的 inject 路径先 `ignore(sync_db_lessons(...))` 再检索，因此新进程读不到。放宽回灌条件即把缺口堵在源头。
- **三态对齐**：落库（BUG-140）→ 回灌（BUG-141）→ 检索（既有 `lookup_injected_assets_in`）闭环。

## 证据（L4）

1. **白盒锁修前红**：临时把过滤改回只 `[lesson]`，`moon test --target js src/server` → `fist-mbt_wbtest.mbt:64:7-64:23 FAILED: 0 != 1`，`Total tests: 172, passed: 171, failed: 1`（唯一红的是新锁）。
2. **白盒锁修后绿**：改回修好 → `172 passed / 0 failed`。
3. **跨进程探针修前红**：临时库 `temp/fix140-sub140.db` 上旧过滤重建后，同一探针得 `INJECTED_GOALS=[] / INJECTED_COUNT=0 / CROSS_PROC_INJECT_HIT=False` + AssertionError。
4. **跨进程探针修后绿**：修好后 `TOOLS_TOTAL=134`、`INJECTED_GOALS=["[asset]code-review-probe"]`、`INJECTED_COUNT=1`、`CROSS_PROC_INJECT_HIT=True`、`SNAPSHOT_HAS_ASSET=True`、`BUG141_CLOSE=PASS`。
5. **活库实证**：live `fist-mbt.db` 注册 8 条 `[asset]`（code-review / systematic-debugging / tdd / spike / plan / research-paper-writing / requesting-code-review / subagent-driven-development），只读 sqlite `WHERE goal LIKE '[asset]%'` count=8；`scripts/check_skill_inject.py` 由 exit 2（档案面空自拒）转 exit 0。
6. **已装 skill**：`~/.agents/skills/fist-mbt` SKILL.md `tools=134 version=0.3.6`，sha256 与 `plugins/deepseek-harness/skills/fist-mbt/SKILL.md` 逐字节相等。

## 遗留风险

- 8 条生态资产 `score=0`（走默认值）；`check_skill_inject` S3 不校验 score 故仍 PASS。若需 score 非零，带参重跑会生成新 id，旧 8 条仍在（计数 >8）。
- `fist-mbt.db-wal` 备份是复制瞬间的形态；活库正被 server 进程持有，备份只作只读回退，未验证可直接挂载恢复。

## 后续建议

- 把 `evolve_asset_register` 的 `score` 默认值从 0 抬到 0.5，避免生态资产在 `evolve_snapshot`/排序里沉底。
- 长期可考虑：给 `sync_db_lessons` 的过滤加一组常量前缀白名单（`[lesson]`/`[asset]`/`[principle]`），避免以后再出现「落库了但不回灌」的缺口。

## 来源

- 账本：`memory/bugs.md` BUG-140 / BUG-141（均 FIXED，小记点名整批）。
- 修复：`src/server/server.mbt`、`src/server/evolve_lesson.mbt`、`src/server/fist-mbt_wbtest.mbt`。