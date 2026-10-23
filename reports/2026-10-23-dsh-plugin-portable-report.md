# DSH 插件安装面可移植化 + 当前面路径硬编码清零（报告）

- 日期：2026-10-23
- 分支：`slave/dsh-plugin-portable`（基线 `788c5823` = gitcode/master）
- 设计：`docs/design-dsh-plugin-portable.md`

## 结果摘要

1. **DSH 安装面双态化**：跟踪真源改为 `.dsh/fist-mbt-plugin/cordis.patch.yml.tpl`（模板，只含
   `{{FIST_MBT_CLI}}` / `{{FIST_MBT_ROOT}}`，零绝对路径）；本机渲染件 `cordis.patch.yml` 由
   `scripts/render_dsh_patch.py` 按脚本位置反推仓根生成并已 gitignore。宿主对 stdio 的
   `args`/`cwd` **不做变量插值**（实测 asar 内 mcp-client 只读 command/args/cwd/env 四键），
   所以「每台机器渲染一次」是唯一不写死机器的装法。
2. **D1 判据改判**：`check_host_installable.py` 的 DSH 档改为「模板档（禁止本机路径 + 占位符齐全
   + 合成渲染后仍过严格档）」+「渲染件在场时严格档；缺席是干净检出合法态」——干净 CI 不再因
   缺本地渲染件自拒。
3. **当前面硬编码清零**：`scripts/{fist_mbt_mcp_client,_run_check_t0r21,tmp_merge_batch}`、
   `plugins/source/SKILL.commander.md`（→ 四宿主重投影）、`AGENTS.md`、`docs/SOP.md`、6 份
   docs 现状文档、`src/server` 3 文件注释 + 3 个测试夹具——机器身份前缀（工程目录名 / 用户名）
   全部清零，**绝对路径形状保留**（夹具断言语义不变）。
4. **新回归锁**：`scripts/check_hardcoded_paths.py`（当前面禁止本机身份路径；豁免只追加历史 /
   构建产物 / 本地产物 / `.mbti`），已接 CI（带 `position-why` 锚点，位置棘轮 34 未升）。
5. **顺手修存量红**：`check_scripts_index.py` 基线就有 5 个未登记脚本（`check_memory_log_dup.py`
   等），本 PR 补齐登记，该判据转绿。

## 证据（本机实测）

| 判据 | 结果 |
|---|---|
| `python scripts/check_hardcoded_paths.py --selftest` / 全量 | rc 0 / PASS（扫描 547 文件） |
| `python scripts/render_dsh_patch.py --selftest` | rc 0（T13 曾当场抓住模板注释里的 `E:/…`，已修） |
| `python scripts/check_host_installable.py --selftest` / 全量 | rc 0 / PASS |
| `python scripts/check_plugin_sync.py` | PASS（4 宿主 / 64 文件 / 170 工具 / v0.3.10） |
| `python scripts/check_doc_surface.py` | PASS（J6-J15） |
| `python scripts/check_scripts_index.py` | PASS（补齐 5 条存量） |
| `python scripts/check_ci_step_position.py` | PASS（34/34，未升档） |
| `python scripts/moon_test_env.py --target js` | **1413 / 1413 passed, 0 failed** |
| `moon check --target js src/server` | 0 errors |

## 资源消耗

- 模型：DSH 会话内同机完成（无外部 API 调用）。
- 工具：moon 0.1.20261016（check/info/test）、Node v25.2.1（经 `moon_test_env.py` 剔 node.cmd 垫片）、Python 3.13。
- 工时：单轮；主要耗时在全量测试（~2 min）与四宿主重投影。

## 任务分配记录

- FIST 任务：ns `dsh-plugin` 根任务（publish → claim → execute → submit；verify 留人类终审）。
- 子代理：无（路径清零面需要逐条判据对齐，拆分反而增加合并风险）。

## 遗留风险

1. **本机 fmt/info 世代与 CI nightly 不同**：`moon fmt` 会重排全仓 355 个文件（BUG-388 家族），
   本 PR 已回滚这些 churn，只保留目标改动 ⇒ 提交门禁的 fmt 面依赖 CI（Linux nightly）。
   若 CI fmt 判红，按既有口径以 CI 为准重排一次。
2. **渲染件不在跟踪面**：别人 clone 后需先 `python scripts/render_dsh_patch.py` 再装 DSH 插件
   （README/模板注释都已写；`check_host_installable` 会点名这一步）。
3. **面向 registry 的一键安装仍缺最后一步**：npm/tarball 包需要把预构建 `fist-mbt.js` 打进包
   并在 postinstall 里渲染（或改造成 Cordis host 插件）。本 PR 只解决「跟踪面不再硬编码」这个前置。
4. `.mbti` 未随注释改动重生成（`moon info` 生成面与 CI 世代不同、且 .mbti 不含 doc 注释 ⇒ 无语义影响）。

## 后续建议

1. 合入后跑一次 `python scripts/render_dsh_patch.py`（本机），DSH 重连即用新安装面。
2. 下一步（另开 PR）：npm 包形态（`bin` + 预构建 JS + postinstall 渲染），再提
   `awesome-dsh-plugin` 目录 PR 让市场可搜到——那条需要 npm token 与别人仓的 PR 权限。
3. 把 `check_hardcoded_paths.py` 的豁免面（docs 现状文档）逐步收窄。

## 超额内容

- 补齐 `scripts/README.md` 里 5 个存量未登记脚本（基线红转绿）。
- 把 `fist_mbt_mcp_client.py` 的 JS 产物解析改为 `<repo>/_build → %LOCALAPPDATA% → dist` 三级回退，
  开发机未发布改动也能直连。

## 来源

- DSH bundle 安装规格与宿主行为：本机 `~/.dsh/profiles/web/package.json`、`dshmarket` README、
  `app.asar` 内 `@deepseek-ai/dsh-mcp-client` stdio 分支（2026-10-23 实测）。
- 本仓口径：`docs/2026-10-20-slave-dev-playbook.md`、`scripts/README.md`、
  `scripts/check_host_installable.py`、`scripts/check_ci_step_position.py`。
