# 2026-10-20 副机汇报 — moonc 0.10.16 `Result` API 适配（BUG-328）

分支：`slave/fix/moonc-0.10.16-result-api`（base = `gitcode/master` @ 34ce658）
任务包：目标=让 HEAD 在现行 moonc 下恢复可编译；边界=只动报错文件本身；验收=`moon check --target js` 0 error；回传=结论/证据/分析/缺口/建议。

## 结果摘要

- 16 个测试文件、110 个 `is_ok()/is_err()` 调用点迁到本仓既有惯用法 `assert_true(x is Ok(_))` / `assert_true(x is Err(_))`。
- `src/store/store_sqlite.mbt::assistant_from_row` 拆除已移除语法 `try? expr`（3 errors → 0）。
- `moon check --target js --json`：**status=success，diagnostic_errors=0**（基线 26 errors），`moonfmt` 直调后所有改动文件幂等通过。
- 合起来这一单消掉的是 CI `Check (js)` 那一步的 26 个 error —— CI 装的正是 0.10.16，所以这一单直接对应 master 的红。

## 资源消耗

- 子代理 1 个（`result-api-migrator`）：54 tool uses / 605s。指挥官侧：shim 与 stdlib bundle 排查、判据复跑、`.mbti` 噪声 revert、文档面与提交。
- 工具链侧一次性投入（不落仓）：`~/.moon-shim/shim.exe`（csc 自建 argv 剥离 shim，4608 B）绕过 moonc 的 `\\?\` ICE；`~/.moon/lib/core/_build/js/release/bundle` 按 `build/` 补齐并把 `all_pkgs.json` 的 `\\?\` 化石路径反解。

## 任务分配记录

| 子任务 | 承接 | 结论 | 终审 |
|---|---|---|---|
| 111 处 `is_ok/is_err` 迁移 | result-api-migrator | 110 处改、1 处（issue_scan_wbtest:84）判为测试语料字符串保留 | 指挥官复跑 `moon check --target js --json` = 0 error，并逐条核对 `assert_*` 计数 HEAD↔现状全等 |
| `store_sqlite.mbt` `try?` 拆除 | 指挥官 | 按可达性论证恒 `Some` 不漂语义 | 同判据覆盖 |
| 格式化 | 子代理 + 指挥官 | `moon fmt` 本机也 ICE，改直调 `moonfmt.exe` | `store_sqlite.mbt` 指挥官补跑 `-w` 后幂等 |

## 遗留风险

1. **`moon test --target js` 未能本机自证**（BUG-329：安装缺 `bundle/core.core`，连最小工程都红）。运行时行为以 CI 为准；PR 已如实标注「本机门禁未覆盖 test/build」。
2. **warning 面 1920 条为仓库存量**（code 20 deprecated StringView 904 / code 25 test_unqualified_package 803 / code 79 implicit_impl_as_method 63 为头部三种）。金条要求「零 WARNING」在这一版工具链下对本仓是全仓级工程，不属本单边界。
3. **同名文件文本冲突**：`memory/2026-10-20.md` 与分支 `slave/misc/...`（BUG-327）各写了一段；`memory/bugs.md` 的 BUG-325 在 `slave/fix/migrate-selftest-ice-routing` 上有一处重号。合并时两段都要留，重号那条改判 DUPLICATE。
4. **`.mbti` 的 `Int`→`Int32`、源码签名的 `Int`→`Int32` 都未入本提交**（BUG-330）。这版 `moonfmt` 会把 `Int` 规范化成 `Int32`，意味着 `moon fmt --check` 在 0.10.16 下对**整仓**红；要让绿是一次全仓 `moon fmt`，与本单正交，不该混在 API 适配里。本单 17 个文件里除这一格外无其它格式差异（逐文件 `moonfmt -o` 对照已核）。

## 后续建议

- 合并顺序：`misc(BUG-327)` → `fix(migrate-selftest)` → `fix(moonc 0.10.16)`，把 `memory/` 冲突集中到最后一跳。
- 要恢复本机的 test/build 自证能力，只有两条：从主机拷含 `core.core` 的 `~/.moon/lib/core/_build`，或在可联网处装回本仓钉版 0.1.20260920。二者都是机器级动作，按金条四只出方案。
- `check_scripts_index.py` / `check_doc_surface.py` 这类守卫缺 `--selftest`，建议与 BUG-327 后续一并补，避免「判据自己坏了不吭声」。

## 超额内容

无。未做：全仓 warning 清零、`moon info` 刷新 `.mbti`、删除 `_run_check_t0r21.py`（不可逆，留指挥官）。

## 来源

- 本机实跑：`moon check --target js --json`（temp/check_after.json，未入库）、`moonfmt.exe` 直调幂等核对、最小工程 `probe/probe` 的 LinkCore 复现。
- 子代理回传：`result-api-migrator`（110 处迁移清单、26→0 error 对照、`.mbti` 副作用自曝）。
- 版本事实：`moon version` = moon 0.1.20261016 (1af328f)，`moonc -v` = v0.10.16+b1a0e846e，`~/.moon/lib/core/moon.mod` version = 0.10.16+b1a0e846e。
