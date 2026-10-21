# R32 · 回归验证自有接线 + 修复 patch_esm_main.py --help 崩溃

- 日期：2026-10-21
- 性质：修复/验证（fix_and_merge + verify）
- 结论：**并发 agent 改码后，我 R29 接线的两个守卫仍 PASS、真 selftest 21 个全过（0 真回归）**；抽检脚本误伤的 2 个 FAIL 中揪出一个真 bug——`patch_esm_main.py --help` 会把 `--help` 当目标文件名抛 FileNotFoundError，已修复（commit `c6d1816`）。

---

## 一、回归验证自有接线（R29 → R32）

并发 agent 195 脏工作树改码后，我 R29 接进 CI 的两个守卫**必须**确认仍成立：

| 守卫 | 结果 |
|---|---|
| `check_desc_enum_sync` | PASS exit=0（描述侧 enum 同步，登记项全一致） |
| `check_upgrade_installer` | PASS exit=0（G1 真源在 VCS 可视面 / G2 现状面零旧引用 / G3 纪律针全在） |

**我 R29 的接线决策在并发改码下仍成立**。

## 二、真 selftest 全绿（0 真回归）

抽检 `scripts/` + `scripts/blackbox/` 全部 `check_*.py` 的 `--selftest`：

```
selftest 通过=21  跳=10  失败=2（实为扫描误伤）
```

**2 个"失败"逐条排查均为扫描脚本误伤，非真回归**：

| 脚本 | "FAIL" 原因 |
|---|---|
| `check_badge` | 需位置参数 `<moon_test_log> <README.md>`，不支持 `--selftest`；exit=1 是**用法错** |
| `patch_esm_main` | **根本不是守卫**，是构建补丁脚本；`--selftest` 被当目标文件名 |

排查第二个时暴露真 bug（见下）。

## 三、修复 `patch_esm_main.py --help` 崩溃（commit `c6d1816`）

### Bug
```
$ python scripts/patch_esm_main.py --help
  File ".../patch_esm_main.py", line 59, in patch
    raise FileNotFoundError(f"not found: --selftest (先 moon build --target js)")
```
`--help` 被当目标文件名，进 `patch()` 抛 FileNotFoundError 并打印 traceback——**不是友好的用法提示**。

### 修复
```python
if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
    print(__doc__)
    sys.exit(0)
```

### 验证
```
--help exit=0（打印 docstring）
-h exit=0
无参 exit=0（自动发现 _build cli.js，"up to date" 幂等）
py_compile exit=0
check_scripts_index exit=0（工具类辅助代码索引完整，零回归）
```

**无参/真实路径行为完全不变**（幂等 "up to date" 路径保留），只新增了 `--help/-h` 友好分支。

## 资源消耗

- 2 次我 R29 接线的守卫真跑
- 1 次 27 脚本 selftest 抽检（21 过 / 10 跳 / 2 误伤）
- 1 次 `patch_esm_main.py` 读+改+验证（py_compile + 3 路退出码 + check_scripts_index）

## 任务分配记录

- 无新派单。src/server 仍 36 脏（R19 第十九轮）。

## 遗留风险

1. **src/server 36 脏（十九轮）**：issue_scan 家族 6 条（327/333/345/346/347/348）+ BUG-339 仍压在脏区。
2. **BUG-339 仍 OPEN**：并发 agent `f6e4019` 独立复核确认 commit-pairing 死锁未解。
3. **fmt 门强度未恢复**：技术前置已消（R31 实测），撤 `continue-on-error` 须等 WIP 收口 + 一次 nightly 全仓重排确认。R31 已把证据写进 ci.yml 注释。
4. 全仓 .mbt 子系统仍在并发脏区，无法安全扫描寻虫（R30 已用干净子系统确认 issue_scan FP 噪音）。

## 后续建议

1. **规则层批次优先级**（R30 实证 264 条 100% FP 后第三次强调）：src/server 清空后第一批落地 BUG-345/346/347/348。
2. `check_badge` / `check_test_sync` 需位置参数，属**刻意设计**（读 moon_test.log），不是守卫缺口——别把它们当"没接 selftest"。
3. 建议给 `check_*.py` 统一 `--help` 支持（本次修的 `patch_esm_main` 是首个有该支持的脚本族例外，其余守卫族仍无 `--help`），但这属低优先级 tidy，不阻塞。

## 来源

- 发布版真跑回执：`check_desc_enum_sync` PASS / `check_upgrade_installer` PASS（2026-10-21 10:24）
- `check_badge --selftest` 用法回执（需位置参数）
- `patch_esm_main.py` L57-80 修复前后对比（新增 `--help/-h` 分支）
- 本会话 R22/R24/R26/R27/R28/R29/R30/R31 提交：`c7934f3` / `b4665e2` / `a15ab01` / `d5464bb` / `0b9c649` / `8ab683e` / `2b385ad` / `167ac5c`