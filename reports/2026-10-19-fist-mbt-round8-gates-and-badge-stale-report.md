# Round 8 · 全门禁巡检 + README 徽章陈旧修复 + BUG-327 part 1 上线状态核验

- **时间**：2026-10-19 10:45（Asia/Shanghai）
- **模式**：验证 / 清整（Round 8 / 256）
- **HEAD**：5dcdaaa（Round 7）
- **结论**：全门禁套件巡检；抓出并修复一处真实陈旧（README 中文徽章 1108→1334）；核验 BUG-327 part 1 的实际上线状态（尚未上线，留待并发收口后从干净 HEAD 重建）。

---

## 1. 全门禁巡检结果（独立复跑）

| 门禁 | 结果 |
|---|---|
| `check_doc_surface.py` | **PASS**（170 工具 / v0.3.9 / J6~J15 全绿） |
| `check_tools_sync.py` | **PASS**（server.mbt 注册 170，AGENTS/README/deliverable/scoring_rubric 对齐；扫现状面 144 份） |
| `check_plugin_sync.py`（cl7） | **PASS**（4 宿主 / 64 生成文件 / 170 工具 / v0.3.9 / 启动参数真源 .mcp.dev.json） |
| `check_badge.py` | **首跑 RED → 修复 → PASS** |
| `check_test_sync.py` | PASS（Round 7 已验，本轮无 docs 计数变更） |

---

## 2. 真实清整：README 中文徽章陈旧

### 2.1 现象

`check_badge.py temp/mt7.log README.md` 首跑：

```
BADGE-STALE: README 徽章 1108/1108 ≠ 实际测试数 1334/1334。
```

`README.md:8` 徽章 `tests-1108%2F1108`，而实测 `1334/1334`。

### 2.2 根因

**中英两版长期不一致**：`README_EN.md:9` 早已是 `tests-1334%2F1334`（Round 7 的 12 处 1333→1334 同步里含徽章），而中文 `README.md` 的徽章从 `218/1108` 一路递增却**从未有人同步到 1333**。

**这是我的盲区**：Round 5/6/7 反复报「1333 / 1334 全绿」，但**从未跑过 `check_badge`**——只跑了 `check_test_sync`（它核对的是文档里的「测试总数声明」，而 shields 徽章 `tests-N%2FN` 走的是另一条解析路径）。`check_badge` 是 ci.yml JS 轨门禁之一（见 AGENTS.md 守卫族清单），此前一直红着没人读 = 红着没人读等于没锁。

### 2.3 修复

`README.md:8`：`tests-1108%2F1108` → `tests-1334%2F1334`（1 行）。`README.mbt.md` 无徽章（已确认，无遗漏）。

复跑：

```
PASS 徽章一致：README tests-1334%2F1334 == 实测 1334/1334
PASS 自检注释一致：README 『→ Total tests: 1334, passed: 1334』 == 实测 1334
rc=0
```

---

## 3. BUG-327 part 1 上线状态核验（dogfood）

### 3.1 真实调用

`ocr_scan subcmd=files path=src/server/ocr_scan.mbt` → 运行中 server 返回：

```
{"ok":true,"ocr_available":true,...,"exit_code":0,
 "stdout":"...reviewable_count:0, excluded_count:1...exclude_reason: unsupported_ext...",
 "ocr_reviewed":false,
 "notice":"scan/files 回执 reviewable_count=0 但 excluded_count=1：全部文件被二进制扩展名白名单拦下（unsupported_ext(1 份)），LLM review 未真正执行"}
```

### 3.2 结论

- **信息面早已 fail-closed**：`ocr_reviewed:false` + `notice` 双通道明确说「LLM review 未真正执行」。运行中的 server 已带 `ocr_fake_green_check` 逻辑。
- **我的 part 1 只把顶层 `ok` 布尔对齐到该信息面**（`ok = okk ∧ reviewed`），修的是「只看 `ok` 的门禁会被骗」这一条窄缝。
- **但顶层 `ok` 仍为 `true`** ⇒ **server 未从 5dcdaaa 重建，part 1 尚未上线**。`dist/fist-mbt.js` 时间戳停在 2026-10-18 10:40。

### 3.3 为何本轮不重建 dist

1. **重建源污染**：直接 `moon build` 会从当前工作树打包并发 agent 的未提交代码（`server.mbt` / `omega/*` 等）进 dist。
2. **重启中断**：重建后要让运行中 server 生效需重启 MCP server，会打断本会话自身依赖的工具（含本工具）。
3. **先例**：前次 dist 提交 `47b92be` 的惯例是「构建自干净 HEAD（git worktree）零编译错误」——干净 HEAD 才不含并发 WIP。

**处置**：留待并发 agent 收口后，从干净 HEAD（5dcdaaa，已含 part 1）重建 dist 并提交。届时 `ocr_scan` 顶层 `ok` 才会对 `.mbt` 假绿返回 `false`。

### 3.4 可编译性确认

`moon check` 全仓 = **rc 0，0 errors**（2067 warnings 全 deprecated）→ 并发 agent 的 WIP 已可编译，dist 重建不存在编译阻断。

---

## 4. 账本 OPEN 条目归属核查

为避免在错误项目上修 bug，逐个核对了本仓相关 OPEN 条目：

| BUG | 归属 | 是否本仓 |
|---|---|---|
| BUG-327 | ocr_scan / require_ocr | ✅ 本仓（part 1 已完成，part 2 待 server.mbt 收口） |
| BUG-324 | `actions/vools/actus.verify.actus.md` | ❌ 兄弟项目 vools |
| BUG-325 | `crates/p5c/src/parser/item.rs` | ❌ 兄弟项目 p5c |
| BUG-326 | `crates/p5c/src/eval/expr.rs` | ❌ 兄弟项目 p5c（已 FALSE_POSITIVE 记入 Pentad 库） |
| BUG-273/274/275/276 | p5c 类型推断 | ❌ 兄弟项目 |
| BUG-321 | p5c BlockExpr 继承 | ❌ 兄弟项目 |

⇒ **本仓当前可独立拥有的 OPEN 仅 BUG-327**，其 part 2（`require_ocr` 门加 `.mbt` 可审性 fail-closed）因 `server.mbt` 被并发 agent 修改仍受阻。

---

## 5. 并发 agent 隔离

- 未提交文件 **20 个**（并发 agent）：`src/server/server.mbt`、`src/omega/{moon.pkg,omega_tool.mbt,omega_tool_test.mbt}`、`src/server/issue_scan_wbtest.mbt`、`src/evidence/`（untracked）、`memory/2026-10-18.md`、`scripts/{check_test_sync.py,fist_mbt_mcp_client.py,mcp_tool_tour.py,ns_route_probe.py,store_isolation_probe.py}` 等。
- 本轮仅改动 `README.md`（徽章 1 行）+ `memory/2026-10-19.md`（Round 8 段）+ 本报告。均非并发 agent 文件。
- 全仓 `moon fmt --check` 仍 rc=-1（并发 agent `src/omega/omega_tool.mbt` WIP 的 `git --no-index` 失败），pre-existing；本轮无 `.mbt` 改动，无 fmt 门需求。

---

## 6. 资源消耗

- 门禁套件 5 项（3 PASS 复跑 + 1 RED→PASS 修复 + 1 PASS 复述）
- 真实修复：`README.md` 徽章 1 行（1108→1334）
- 记忆：`memory/2026-10-19.md` 追加 Round 8 段
- 报告：`reports/2026-10-19-fist-mbt-round8-gates-and-badge-stale-report.md`

---

## 7. 遗留风险

1. **BUG-327 part 1 未上线**：源码已修并提交（5dcdaaa），但 `dist/fist-mbt.js` 未重建，运行中 server 顶层 `ok` 仍 `true`。须等并发 agent 收口后从干净 HEAD 重建。
2. **BUG-327 part 2 未做**（`require_ocr` 门），因 `server.mbt` 并发脏。
3. **P1 发布载荷面**仍红（rc=1）：并发 agent `src/evidence/` 5 文件 + 3 脚本未跟踪又未 ignore ⇒ `moon publish` 会公开。凭据形状 0 命中。等用户裁决（入库 vs `.gitignore`）。
4. **3 项用户裁决未动**：① `15fe403` 撤回 `git reset --soft HEAD~1`？② BUG-268 summary 与 15fe403 标号错配？③ `src/evidence/` untracked？
5. **全仓 `moon fmt --check`** 被并发 agent `src/omega/omega_tool.mbt` WIP 挡住（rc=-1），并发收口后需重排一次恢复 fmt 门强度。

---

## 8. 后续建议

1. **并发 agent 收口后**：从干净 HEAD 重建 `dist/fist-mbt.js`（让 part 1 上线）→ 补 BUG-327 part 2（`require_ocr` 加 `.mbt` 可审性判据）→ 关 BUG-327 FIXED。
2. **补跑 check_badge 进日常验证清单**：本轮盲区（多轮报 1333/1334 却从没跑 check_badge）说明「check_test_sync 绿 ≠ 全部文档门禁绿」；建议在验证脚本里把 badge 一并纳入。
3. **处理 P1 发布载荷面**（等用户裁决）。
4. **守卫窄面遗留**（`substring(start=n-n%k,end=n)` / `start=p,end=p+2` 仍误报，本仓零实例）：`src/server/issue_scan.mbt` 目前干净可编辑，可在下轮做 TP 锁或收窄规则（注意 `issue_scan_wbtest.mbt` 是并发 agent 的，勿动）。

---

## 9. 来源

- 代码：`README.md`（徽章 1 行）
- 记忆：`memory/2026-10-19.md`（Round 8 段）
- 门禁输出：本轮 5 项独立复跑
- 工具回执：`ocr_scan`（dogfood，`subcmd=files`，`path=src/server/ocr_scan.mbt`）
- 测试日志：`temp/mt7.log`（check_badge / check_test_sync 输入）