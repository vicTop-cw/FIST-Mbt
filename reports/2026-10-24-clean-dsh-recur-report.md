# 汇报 R3：修复合并回归 + 揪出 pre-commit 自证沙箱污染宿主仓的判据 bug

- 日期：2026-10-24
- 分支：`slave/clean-dsh-recur-r3`（基线 `1c5c1134` = gitcode/main）
- 设计边界：`docs/design-push-guard-sustainability.md`（R2 版仍有效，本轮是其后继收口）
- FIST：ns `self-iterate-r3` T0

## 结果摘要

1. **合并回归修复（寻虫→修复）**：合并通道把某台机的 `F:/` 渲染件 `.dsh/fist-mbt-plugin/cordis.patch.yml`
   重新跟踪回 main（BUG-389(2) 病根**换盘符复发**）。旧词表尺只认已知 token，抓不到未知机器根 ⇒
   尺子加 **D 面结构锁**：D1 `.dsh/**/cordis.patch.yml`（非 .tpl）被跟踪即红（与形状无关）；
   D2 `.dsh` YAML 值面盘符即红（占位符/`${}` 豁免）。渲染件再脱跟踪 + gitignore 钉死；
   tpl/render/D1 统一 launcher 形状（对齐社区层 b5c8a366）。
2. **新判据 bug 实踩并修复（本轮最大寻虫成果）**：提交时 pre-commit 钩子调
   `check_merge_markers.py --selftest`，其沙箱 `git init/add/commit` **继承了钩子导出的
   `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_CONFIG_*`** ⇒ 三发合成 "fixture" 提交直接写进宿主 HEAD、
   宿主 local config 被注入 `user.name=t`。任何在钩子里自跑 git 的沙箱判据都是同形地雷。
   修法：`sandbox_env()` 剥 GIT_* 控制变量 + `GIT_CONFIG_NOSYSTEM`，沙箱全部 git 调用走 scrubbed env；
   新增 **C7 正向锁 + 变异对照**（毒化环境下 new_repo 不得动宿主 HEAD；不 scrub 裸跑必须泄漏，
   否则正向锁是假绿）。**端到端实证**：修复后经完整钩子提交，HEAD 恰一发干净提交、无 fixture、config 干净。
3. **三面接面补齐（清整）**：ci.yml 接 Push-guard/Machine-path/render 三格（position-why 块内，棘轮 34 未升）；
   run_guards 点名 `check_direct_push --selftest`（禁自动裸跑格读 stdin 挂管道）；README 登记 +
   BATTERY-REGISTRATION 校正到现读 `105/47/67/0/74/27/6`（顺带修 main 自身一笔登记落后）。

## 资源消耗
- 模型：DSH 会话同机；moon 0.1.20261016（仅 moon check 依赖，本单零 .mbt 改动故未触发）；Python 3.13；git。
- 工时：单轮；含一次被自家钩子拦下并当场转化为寻虫成果。

## 任务分配记录
- ns `self-iterate-r3` T0 publish（fist.py 网关，主检出锚点）；claim/execute 板书受跨进程 ACL 写门
  （can_write=0，fail-closed by design，不强绕）——交付证据以 PR 正文承载。
- 子代理：无（钩子污染需逐帧归因）。

## 遗留风险
1. **宿主 config 已恢复**（注入的 `user.*` 已 unset），但同形地雷可能还有第二处：凡「判据在钩子里
   跑真 git」的族（`check_branch_ancestry`/`check_merge_loss` 等也用临时 git 仓）应逐一过 `sandbox_env`——
   本单只钉了实踩到的 `check_merge_markers`，其余在 CI/电池里不挂，但**建议下一单普查**。
2. main 上的旧注入残留 `branch.slave/clean-dsh-recur-r3.*` 配置条目无害（分支注册），未清。
3. `render_dsh_patch --check` 依赖本机 `_build`/launcher 在场；干净 CI 上只跑 `--selftest`（已如此接线）。
4. CI 三格失败归因（基线 dc_3 / native BUG-133 / slave-task 锚点）见 PR #28 追评，同形状适用于本 PR。

## 后续建议
1. 合并后跑 `python scripts/render_dsh_patch.py` 重生成开发层渲染件；`.git/hooks` 若还有手装 pre-push，
   `python scripts/install_git_hooks.py --install` 统一回跟踪面版本。
2. 普查「钩子里跑真 git」判据的 env 隔离（见遗留 1）。
3. main 上 `check_push_guard` 与社区层的形状合一（本单已做 tpl/render 侧）。

## 超额内容
- 被 pre-commit 拦下的瞬间没有 `--no-verify` 绕过，而是把拦路红转化成了修复对象——这正是
  BUG-388/389 一族「钩子必须出声」设计的价值兑现。

## 来源
- 本机实测：fixture 劫持现场（git log 0da08157 等三发，已 reset 清除）、宿主 config 注入与恢复；
- `scripts/blackbox/check_merge_markers.py` selftest C7 与变异对照读数；
- gitcode/main `1c5c1134` / GitHub PR #17、#28 历史。
