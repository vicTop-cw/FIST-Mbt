# 2026-10-11 · improvement-plan-20261010.md v3 五方向落地核对报告

## 结果摘要

用户问「5 个方向计划都完全搞定了？」，要求逐项核实。**结论：没有全搞定**——收口的是工具/机制，有 **4 项实际没做**、**3 处遗留**。以下均为真源实测（grep 源码 + `evolve_snapshot` 回读），不引用未验证转述。

## 用户点名三项的核对

### ① 路由加了 atomcode freebuff？→ 计划里没这一项，也没实现
- **atomcode 是外部编码执行器**（`executor_run` 只收 `aider|atomcode`，见 `src/executor/cli_argv.mbt`），**不是模型池**。
- 模型的"免费缓冲"是 `free_pool`/`paid_pool`：`src/router/` 下 28 处引用，**多池机制已实现**（`router_config.mbt` / `router_state.mbt` / `model_router.mbt`）。
- **但计划 §3.1 说的默认池 `free_pool: [anon-opencode, eac, kilo]` 没硬编码进 `router_config.mbt`**（grep `default_free_models|anon-opencode|"eac"|"kilo"` 零命中）——机制在、默认清单没预置，靠调用方 `config_json` 传。
- atomcode 与免费池是**两套体系，未打通**。

### ② 多 agent 对话自驱？→ 工具在，真辩论没跑过
- 六顶帽 4 工具已落地（`611cd24`）：`hat_list` / `debate_convene` / `debate_register` / `debate_verdict`，真源 `src/ops/ops_hats.mbt`，白盒 `ops_hats_wbtest.mbt` 9 + `debate_tools_wbtest.mbt` 10。
- 但计划 §4.1 明确把「每顶帽子 = 一个 subagent」的**编排交给 DSH 的 `subagent`/`workflow`**，fist-mbt 只做裁判台（收判决 + 收敛 rate + `terminal_gate=user`）。
- **工具是裁判台，不是辩论本身**；仓库里没有一次真跑的多帽辩论记录（`docs/debate-skill.md` 与 `debate_tools_wbtest.mbt:184` 里的 `grill-me` 只是示例/夹具）。

### ③ 引入外部 skills？→ 8 条已注册，grill-me/superpowers 没引入
- `evolve_snapshot` 回读：21 资产，含 tdd / requesting-code-review / subagent-driven-development / systematic-debugging / spike / plan / research-paper-writing / ideation（D4=默认 A：只注册不进库，P0-c 完成）。best = `[asset-test-driven-development-2026-10-10T03:57:16Z score=0.8]`。
- **§5.2 第 3 项 grill-me / superpowers 一条都没注册**（archive 里没有；`memory_test.mbt` 的 `[asset-superpowers-x]` 是测试夹具）。
- **§5.2 第 4 项 skill 路由增强（`task_triage` 按 skill 命中度）完全没做**——`task_triage` 仍只按 能力匹配(want)→优先级→重要度→深度。计划自己点名为「真正的新价值」，未落地。

## 其它没做 / 遗留

| 项 | 真源出处 | 状态 |
|---|---|---|
| `model_auth_status` 工具 | 计划 §3.4 cl1 | ❌ 未实现（grep `src/` 零命中；只有 `model_router_status`/`model_router_reset`；守卫 `check_model_auth_no_key.py` 做了但 MCP 工具缺失） |
| Star 门 public_key_hex 离线钉死 | 计划 §3.2 | ⚠ 仅 env `FIST_STAR_GATE_PUBKEY_HEX`，未离线钉死 |
| Star 门 6h TTL | 计划 §3.2 | ⚠ 未实现 |
| 多池默认池预置 | 计划 §3.1 | ⚠ 未预置（见 ①） |

## 已真做完的
P0-a Logo + assets 字节拷贝（`106b421`）✓ · P0-b `mcp_config_scaffold` + `fist-config.html` + `default-fist.mcp.json`（`b0ff63c`）✓ · P0-c skill 安装 + 8 生态资产注册（`fcd9480`）✓ · P1-a 多池机制 + Star 门 D1=A（`7878a5c`）✓ · P1-b 六顶帽工具 + 白盒（`611cd24`）✓ · P2 三守卫 `check_host_installable` / `check_model_auth_no_key` / `check_skill_inject`（`1934472`）✓ · BUG-139/140/141 收口 ✓ · BUG-133 两格闭合（`1f581a7` + 独立复核）✓ · BUG-142 挂账（OPEN）+ 文档口径已改 ✓ · 四必需守卫 `check_plugin_sync`/`check_doc_surface`/`check_tools_sync`/`check_publish_payload` 全 rc=0。

## 后续建议（执行权留用户）
1. §5.2 第 4 项 skill 路由增强（`task_triage` 按 skill 命中度）——纯计算、零 IO，好验证。
2. 补 `model_auth_status` 只读工具（cl1 缺口）。
3. 真跑一次多帽辩论（DSH subagent 编排 3 顶帽子，fist-mbt 做裁判台）——补「多 agent 对话」实证。
4. Star 门两遗留（离线钉 key / 6h TTL）按需。
5. grill-me/superpowers 若要用，先 clone 进 `~/.agents/skills` 再 register（需用户拍板 D4=B）。

## 来源
`docs/improvement-plan-20261010.md`（全文）、`memory/2026-10-10.md`、`src/router/*`、`src/ops/ops_hats.mbt`、`src/server/server.mbt`、`src/server/debate_tools_wbtest.mbt`、`evolve_snapshot` MCP 回读、仓库 grep 实测。