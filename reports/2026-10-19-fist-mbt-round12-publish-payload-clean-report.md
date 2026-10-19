# Round 12 · 消 P1 publish 载荷面红

- **时间**：2026-10-19 11:25（Asia/Shanghai）
- **模式**：清整（Round 12 / 256）
- **HEAD**：2fbe379 → **184c348**
- **结论**：`check_publish_payload` 权威红面 6 条 P1 全部消除，判据转 PASS。

---

## 1. 修复内容

`check_publish_payload`（BUG-127：`moon publish` 打包面=工作树−`.gitignore`，未跟踪文件会被公开）权威红面 6 条：

| 文件 | 判定 |
|---|---|
| `/reports/2026-10-18-fist-mbt-cleanup-report.md` | 旧报告，gitignore |
| `/reports/2026-10-18-fist-mbt-issue-scan-fp-report.md` | 旧报告，gitignore |
| `/reports/2026-10-19-fist-mbt-round3-bug268-fp-cleanup-report.md` | 旧报告，gitignore |
| `/scripts/pol_keeper_run.py` | `_gen.py` 生成物，gitignore |
| `/scripts/_gen.py` | 生成器（无文档引用），gitignore |
| `/scripts/fix_esm_require.py` | 无任何引用，gitignore |

**修法**：逐文件精确点名 `.gitignore`（遵循既有先例——Round 261b 对并发 agent 未跟踪脚本同款处理；Round 261 对旧报告逐文件点名）。

**边界**：文件**保留在工作树**，供并发 agent 自行决定入库。本轮**不提交他人工作、不删文件**，只停止 `moon publish` 公开。

## 2. 验证

### 2.1 修复前（红）
```
VIOLATION P1 ... × 6  （EXIT: 1）
```

### 2.2 修复后（绿）
```
PASS 发布载荷面干净：将随包公开 1066 件，其中未被 git 跟踪的 0 件（另有 25 件点号条目 moon 本来就不打包）
EXIT: 0
```

### 2.3 零回归确认
`check_scripts_index` exit **0**（门通过）。其 FAIL 文本列 `fix_esm_require.py` / `pol_keeper_prompt.md` 未在 `scripts/README.md` 登记——**先存问题**：两文件本就在盘上、本就未登记，与 `.gitignore` 改动无关（该判据扫文件系统不读 .gitignore），零回归。

## 3. 状态变化更正（诚实）

- 记忆（Round 7）称 "`src/evidence/` 5 文件未跟踪"——**已过时**。本轮 `git status` 确认 `src/evidence/` **已不在未跟踪列表**（先前已被入库），本轮无涉。
- 当前未跟踪项仅 6 条（上述，现已 gitignore）。

## 4. 并发 agent 状态

| 项 | 状态 |
|---|---|
| HEAD | 184c348（本轮） |
| `src/server/server.mbt` | **仍 M** |
| 未提交总数 | 14（未变） |
| BUG-327 part 2 | **仍阻塞**（判定需 server.mbt 调 `ocr_effective_ok` 做 require_ocr 门） |

## 5. BUG-327 part 2 为何本轮不写死代码

- part 2 判定逻辑必须在 `server.mbt` 的 `require_ocr` 工具处理器里调用 `ocr_scan.mbt:389` `ocr_effective_ok(okk, reviewed)` 完成 fail-closed。
- 在 `ocr_scan.mbt` 另写一个不被调用的纯函数 = 死代码（编译通过但无任何效果），**不算真进展**，且会在并发 agent 收口后与真接线重复。
- 故不写，等 `server.mbt` 干净后一次接线 + 锁测试。

## 6. 资源消耗

- 判据：`check_publish_payload` ×2（红→绿）、`check_scripts_index` ×1
- 核对：`git status --porcelain --untracked-files=all`、`.gitignore` 全读（124 行）
- 改动：`.gitignore` +10 行（Round 12 块）
- 记忆：`memory/2026-10-19.md` Round 12 段
- 报告：`reports/2026-10-19-fist-mbt-round12-publish-payload-clean-report.md`

## 7. 遗留风险

1. **BUG-327 part 1 未上线 + part 2 阻塞**——寻虫闭环头号阻塞，需并发 agent 先提交 `server.mbt`。
2. **并发 agent 未提交测试 +3**：其提交时徽章须升 1337（其责）。
3. **`check_scripts_index` 先存 FAIL**（fix_esm_require.py / pol_keeper_prompt.md 未登记）——exit 0 门过，未阻塞；如并发 agent 决定入库这两脚本，需补 `scripts/README.md` 登记。
4. **全仓 `moon fmt --check`** 仍 rc=-1（并发 WIP）。
5. 本轮未改 `.mbt` → 无需 fmt / 测试门禁（零回归已由判据 exit 0 佐证）。

## 8. 后续建议

1. **并发 agent 提交 `server.mbt` 后** → 从干净 worktree 重建 dist（part 1 上线）→ 接 part 2 → 关 BUG-327 FIXED。
2. `fix_esm_require.py` 若确为 `patch_esm_main.py` 的改进版，建议合并/登记；否则保持 gitignore。
3. 旧报告若不再需要，可考虑归档到 `docs-archive/` 或删除；保留在 gitignore 面可接受。

## 9. 来源

- 判据：`python scripts/check_publish_payload.py`（红→绿，PASS 1066 件/未跟踪 0）
- 代码：`.gitignore`（Round 12 块 +6 条）、`scripts/_gen.py:130`（生成 `pol_keeper_run.py`）
- Git：`git status --porcelain --untracked-files=all`、`git ls-files reports/`（401 件跟踪）