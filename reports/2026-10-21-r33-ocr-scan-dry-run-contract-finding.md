# R33 · 发布能力一致性验证：ocr_scan dry_run 契约瑕疵 + mode 模板一致性 + --help tidy 覆盖确认

- 日期：2026-10-21
- 性质：验证（verify）
- 结论：**真契约发现——`ocr_scan --dry_run` 恒报 `ocr_available:true`（不探测二进制），而真跑报 `ocr_available:false`（本机 opencodereview.exe 未安装）**。dry_run 的 `ocr_available` 是"未探测的假设"，对"先审后跑"的调用方是误导。另确认 mode_list↔mode_templates 7/7 一致、`--help` tidy 在干净脚本面上已覆盖。真源 `src/server/ocr_scan.mbt` 在并发脏区（src/server 36 脏），**只报不修**。

---

## 一、真契约发现：`ocr_scan --dry_run` 的 `ocr_available` 恒为 true（关键）

### 复现（同一入参，两步对比）

| 调用 | `ok` | `ocr_available` | 说明 |
|---|---|---|---|
| `ocr_scan dry_run=true` | true | **true** | 未探测二进制 |
| `ocr_scan dry_run=false` | false | **false** | 真跑，opencodereview.exe 未安装 |

### 问题

dry_run 路径**不探测 OCR 二进制是否存在**，却回 `ocr_available:true`。工具契约明确要求：

> "不可用时显式降级为『只用 issue_scan』，回执含 `ocr_available=false`"

但这条只在**真跑**路径生效。dry_run 设计意图是"先审后跑"（先看 argv 再决定跑），而它的 `ocr_available:true` 会误导调用方以为 OCR 可用、放心去掉 dry_run 真跑——结果真跑直接失败（诚实降级，`ok:false` 不假绿，这点是对的）。

### 影响与建议

- **影响**：`bugfind` 模式 `require_ocr=true`。在本机（无 opencodereview.exe）该约束**无法满足**——但 `ocr_scan` 真跑诚实降级（`ocr_available:false` + 明确错误 + 不静默成功），说明工具行为正确，只是环境缺依赖。
- **建议**（`src/server/ocr_scan.mbt` 脏，留给 owner/并发 agent）：
  1. dry_run 路径探测 `FIST_OCR_BIN` / 相邻模式定位二进制，探测不到回 `ocr_available:false`（与真跑一致）。
  2. 或者 dry_run 回执里把 `ocr_available` 改为三态：`available` / `unavailable` / `unprobed(dry_run)`，避免误导。

**这是本轮最重要的真契约发现**——通过实测发布能力，发现 dry_run 契约与真跑不一致。

## 二、mode_list ↔ mode_templates 一致（7/7）

- `mode_list` 返回 7 模式，constraints / template_path / forbidden_tools 与 AGENTS.md 表逐项对齐：
  - `polish`：`forbid_new_features:true` + 禁 `publish`/`publish_parallel`/`dag_publish`
  - `tidy`：`forbid_new_code:true`（注意键名是 forbid_new_code 不是 forbid_new_features，与 AGENTS.md 一致）+ 禁同三工具
  - `bugfind`：`require_issue_scan + require_test_corpus + require_ocr`
  - `verify`：`require_api_enum + require_doc_check`
  - `explore`：`require_complexity_scoring + allow_parallel_modes + require_disjoint_files`
- `mode_templates`：`{advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}`, `missing:[]`

**7 模式 ↔ 7 模板（`templates/pipeline_mode_<mode>.md`）完全对齐，无缺失。**

## 三、`--help` tidy 在干净脚本面上已覆盖

普查全部 `check_*.py` 的 `--help`：

| 类别 | 数量 |
|---|---|
| `--help` exit 0 | 20 |
| 需位置参数（显示用法） | 1（`check_badge`） |
| `--help` 崩溃 | **1（`check_test_sync`）** |

- `check_test_sync.py --help` 走 `elif args:` 分支把 `--help` 当日志路径 `Path("--help").read_text()` → FileNotFoundError。
- **但 `check_test_sync.py` 脏（` M`），不能修**（standing constraint）。只记录不动作。
- 更广的干净脚本普查（scripts/ + scripts/blackbox/，跳过脏文件）：**0 个崩溃**——R32 修的 `patch_esm_main` 是干净面上最后一个 `--help` 崩溃点。

## 资源消耗

- 1 次 `mode_list` + 1 次 `mode_templates`（纯读）
- 2 次 `ocr_scan`（dry_run + 真跑，真跑诚实降级）
- 1 次 22 个 `check_*.py` 的 `--help` 普查
- 1 次干净脚本 `--help` 普查（后台，杀错一次因挂在无 argparse 阻塞脚本上，重跑确认 0 崩溃）

## 任务分配记录

- 无新派单。src/server 仍 36 脏（R20 第二十轮）。

## 遗留风险

1. **`ocr_scan --dry_run` 的 `ocr_available` 契约不一致**（本轮真发现）：dry_run 恒 true，真跑看二进制。建议三态或 dry_run 也探测。`src/server/ocr_scan.mbt` 脏，留给 owner/并发 agent。
2. **`check_test_sync.py --help` 崩溃**（真 bug，脏文件）：与 R32 修的 `patch_esm_main` 同类，但文件被并发 agent 占用。记录不修。
3. **本机无 OCR 二进制**：`bugfind` 模式 `require_ocr=true` 在本机不可满足。`ocr_scan` 真跑诚实降级（正确），dry_run 误导（见一）。
4. **src/server 36 脏（二十轮）**：issue_scan 家族 6 条 + BUG-339 仍压脏区。
5. fmt 门 `continue-on-error` 技术前置已消（R31），撤门等 WIP 收口（owner 裁决）。

## 后续建议

1. **优先**：把 `ocr_scan` dry_run 契约问题（一条发现）交给 owner/并发 agent 评估——dry_run 应探测二进制或回三态，否则"先审后跑"是误导。
2. `check_test_sync.py --help` 修复：等该文件清空后，与 R32 的 `patch_esm_main` 同法加 `--help/-h` 分支。
3. 本机装 OCR 二进制（`opencodereview.exe`，放 `../ocr-local` 或设 `FIST_OCR_BIN`）后，`bugfind` 模式的 `require_ocr` 才可满足，issue_scan + OCR 双轨寻虫才能真正跑通。
4. 规则层批次（BUG-345/346/347/348）优先级不变（R30 实证 264 条 100% FP）。

## 来源

- `ocr_scan` dry_run 回执（`ocr_available:true`）+ 真跑回执（`ocr_available:false`，2026-10-21 10:38）
- `mode_list` / `mode_templates` 实跑回执（7/7 一致，2026-10-21 10:37）
- `check_*.py --help` 普查回执（20 过 / 1 需位置参数 / 1 崩溃）
- AGENTS.md「开发模式与模板」表（constraints 对齐基准）
- 本会话 R22/R24/R26/R29/R31/R32 提交：`c7934f3` / `b4665e2` / `a15ab01` / `8ab683e` / `167ac5c` / `c6d1816`