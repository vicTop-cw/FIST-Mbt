---
topics: [sop, workflow]
doc_kind: note
created: 2026-09-24
updated: 2026-10-16
---

# Standard Operating Procedure

## Workflow (7-phase combo cycle)

| Phase | What | Mode |
|-------|------|------|
| 1 | 推进评估 | `advance` |
| 2 | 寻虫（issue_scan + 边界语料） | `bugfind` |
| 3 | 修复 issues + 合并分支 | `fix_and_merge` |
| 4 | 验证（API 枚举 + 文档自洽） | `verify` |
| 5 | 打磨完善（不加新功能） | `polish` |
| 6 | 项目打扫清整 | `tidy` |
| 7 | 探索（按复杂度自选模式） | `explore` |

## 单轮节奏

1. 发布根任务到隔离命名空间（如 `marvis-drive`）
2. 认领 → 执行 → 提交 → 验收 → 归档
3. 报告先行（写 `reports/YYYY-MM-DD-*.md`）
4. 每次交付物落 `git commit` + `git push`

## 多 agent 并发规范

- 使用独立 git 分支隔离（如 `marvis-polish-20261016`）
- `git add` 前必须 `git diff --cached` 审查 staged 内容
- 不要 `git add -A`（会连带暂存其他 agent 的未提交改动）
- 任务描述注明不污染他人工作区

## 测试基线

- `moon test --target js` 全量 = 1978/1978 绿
- 单模块：`moon test --target js src/<module>`
- 环境：`$env:MOON_HOME = "C:\Users\<user>\.moon"`

## 发布

- 部署路径：`_build/js/debug/build/cmd/cli/cli.js`（发布入口）→ `scripts\patch_esm_main.py` → Copy-Item 到 AppData
- 重启 MCP server 后新代码生效

## 代码质量

- 无 TODO/FIXME/HACK 残留
- 无 high/medium 级 issue_scan 命中
- 组合环 `loop_create` + `loop_tick` 自动推进
- `evolve_submit` 沉淀经验教训

