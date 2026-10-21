# FIST-Mbt 驱动 cypy 自驱测试 · Round 1 报告

- **日期**：2026-10-11
- **驱动方**：FIST-Mbt（指挥官模式，136 工具，v0.3.8）
- **目标项目**：`E:\IDEProjects\AI\Cypy`（class-Python→Cython 编译器，flat layout，`cypyc/` 在仓库根、未 pip install）
- **任务**：修复 cypy 全量 pytest 的 **22 个 FAILED**（2778 通过），且不新增回归
- **驱动环**：`cypy-test-drive`（full-iterate，steps=[advance, bugfind, fix_and_merge, verify]，max_rounds=5）→ `goal_reached`

## 结果摘要

**22 failed → 0 failed**，全量清零，无新增回归。

| 读数 | 修前（2026-10-11 基线） | 修后（全量实跑） |
|---|---|---|
| failed | 22 | **0** |
| passed | 2778 | **2800** |
| total | 2800 | 2800 |
| 耗时 | 949.89s | 869.76s |

- **全量验证**（独立验证子代理实跑）：`python -m pytest tests -q --tb=short` → `2800 passed, 2 warnings in 869.76s`，exit 0。
- **指挥官独立终审**（金条八，亲自复跑全部 22 个目标文件）：`480 passed, 0 failed`。
- 22 个失败归因为**三源**，其中**只有 1 条是真实编译器 bug**，另 2 条是 harness/host 环境问题（非判据缺陷）。

## 资源消耗

- **子代理数量**：10+ 个（6 个按簇分派 + 2 个验证 + 1 个最终全量 + 1 个入档 + 若干回归抽检）。
- **改动文件清单**：
  - `cypyc/codegen/cython_generator.py`（唯一源码改动，字节级还原到 HEAD，215769 字节）
  - `scripts/e2e_golden.sh`（+`CY_PYTHON` 解释器注入点，默认值仍 `python`，真实调用行为逐字节不变）
  - `tests/test_build_block_binding_r19.py`、`test_build_block_guard_pointer_r24.py`、`test_build_block_lowering_r20.py`、`test_build_block_yield_scope_r21.py`（测试 harness 注入 `PYTHONPATH`）
  - `tests/test_judge_strictness.py`（测试夹具 WSL 适配）
- **入档（cypy 侧）**：`Find_BUG/BUGS.md` BUG-054、`memory/bugs.md` BUG-160、`reports/2026-10-11/R25-cypy-selfdrive-round1-report.md`、`CHANGELOG.md` R25 条目。
- **fist-mbt 侧自进化**：`evolve_lesson` → `lesson-202610-11.06.07`（`codegen-cleanup` 类目）。
- 未做任何 `git add/commit`（工作树已有 182 个未提交改动，且另一 agent 正并发改 fist-mbt 本体）。

## 任务分配记录

| 簇 | 失败数 | 根因 | 修法 | 复跑读数 |
|---|---|---|---|---|
| **A** judge_strictness | 6 | WSL `bash.exe` 启动时重设 PATH + 变量未进 `WSLENV` 白名单 → 假 python shim 从不执行 → 判据在本机没真跑 | 判据加 `CY_PYTHON` 注入点 + 夹具 `_is_wsl_bash`/`_runnable` + `WSLENV`；判据本身严格性 6 场景实测红绿符合预期、**零断言放松** | 18/18 |
| **B** build_block 族 | 5 | flat layout + 子进程 `cwd=tmp_path` 无 PYTHONPATH → `No module named cypyc` | 4 个测试文件注入 `env["PYTHONPATH"]`（同仓 `test_r5_fix_cli_hook.py::_cli` 同款） | 82/82 |
| **C** corpus_pairs | 4 | **同一 `_use_cdef` 悬空引用**（19 行并发车道污染的一部分，还连带把 `class Box: value: int` 错生成非法 `cdef int value`） | 还原 `cython_generator.py` 到 HEAD 字节级一致（`_addr_taken` 判定），golden/corpus **原封未动**（指纹自证） | 332/332 |
| **D** macro_expansion | 2 | `_visit_LetStmt` 引用已删除 `_use_cdef` → NameError | 改 `node.name in getattr(self,'_addr_taken',set())`（与 `is_const` 分支 1246/1251 逐字同形） | 23/23 |
| **E** stage2 let/var | 2 | 同上 | 同上 | 8/8 |
| **F** generic_callsite + bug30 | 3(→4) | 同上（F 还多查出一个 `test_multiple_type_arguments_parse_and_erase`，一并转绿） | 同上 | 17/17 |

**统一根因（C/D/E/F 共 11 失败 + F 额外 1）**：`cython_generator.py::_visit_LetStmt` 在「带类型标注 + 带初值」分支（L1333/1338）调用 `_use_cdef(node.name)`，但该函数已被删除——全仓 grep **0 定义、仅 2 处悬空调用** → 任何此类 `let`/`var` 声明抛 `NameError: name '_use_cdef' is not defined`。4 个子代理（C/D/E/F）各自独立定位到同一根因并收敛到同一修法，无内容冲突。

**22 失败的真正构成**：
- 语言缺陷：`_use_cdef` 悬空引用 → 11~12 失败（同源）
- harness 环境：flat layout + 子进程缺 PYTHONPATH → 5 失败（B）
- host 环境：WSL bash PATH/`WSLENV` → 6 失败（A）

## 遗留风险

1. **2 个 warning（基线 1）**，均非本次修复引入：① `PytestUnhandledThreadExceptionWarning`——子进程读线程 `UnicodeDecodeError: 'gbk' codec can't decode byte 0xff`（Windows 默认 GBK 解码非 ASCII 输出，harness 环境噪音）；② `PytestRemovedIn10Warning`——`test_build_block_binding_r19.py` 中 class-scoped fixture 用实例方法定义（pytest 弃用提示）。追求「零 warning 收口」需另起一轮。
2. **单点权威读数**：全量 869.76s 只跑了一次，未做多连发稳定性证明。
3. **A 簇修复只在 WSL 路径生效**：CI 原生 bash（`ubuntu-latest`/`windows-latest` Git-bash）侧未复核（但 `CY_PYTHON` 默认值仍 `python`、行为逐字节不变，零回归为实测结论）。
4. **工作树未提交**：进入时已带 182 个未提交改动（含他方并发工作），本轮只做工作树级修复，未 `git add/commit`。`cython_generator.py` 已字节级还原到 HEAD，属「干净修复」，可直接并入提交。
5. **BUG-054/160 仍 OPEN**：本轮只入档，转 FIXED 需下一轮按仓内既有收口口径复核。

## 后续建议

1. **下一轮动 `cython_generator.py` 前先 grep 三个 needle**（`_use_cdef`/`_is_c_native_type`/`is_c_native`），确认无残留悬空引用——「并发车道删定义不删调用点」是本仓结构性坑。
2. **全量 pytest 失败先分诊「语言缺陷 vs harness/host 环境」**，别一律按编译器 bug 入账。本轮 22 失败里 11 是 harness/host，直接按编译器 bug 修会浪费预算。
3. **C 原生类型默认 `cdef` 车道若要转正**：必须按 `CHANGELOG.md` R19-8b 政策**同批重封** 4 条 corpus spec（重算 `fnv1a64` 指纹），否则本修一次回退会让该车道再红。
4. **fist-mbt 阶段 2（`fist-mbt upgrade` 真写盘换二进制）**：待指挥官批准（不可逆，AGENTS.md 只给方案+预案）。

## 超额内容

- 除 22 个目标失败外，顺手修/确认为绿：`test_multiple_type_arguments_parse_and_erase`（F 簇额外查出的隐藏失败）、`class Box: value: int` 附带损伤（C 簇带修）、`test_codegen_verification`/`test_r5_fix_codegen`/`test_generic_types`/`test_generic_class_scope_r17`/`test_stage5`/`test_type_promotion` 回归抽检 99/99。

## 来源

- 子代理回传五段式报告（A/B/C/D/E/F/验证/入档 共 10+ 份）
- 指挥官独立终审实测读数（22 个目标文件 480/480）
- 验证子代理全量实跑：`2800 passed, 2 warnings in 869.76s`
- cypy 入档：`Find_BUG/BUGS.md` BUG-054、`memory/bugs.md` BUG-160、`reports/2026-10-11/R25-cypy-selfdrive-round1-report.md`