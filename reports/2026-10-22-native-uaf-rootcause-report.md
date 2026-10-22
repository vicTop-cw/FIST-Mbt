# native 崩溃根因定位报告：daqing/sqlite stub 的 use-after-free（BUG-133 族）

日期：2026-10-22 · 执行：lead-2 · 环境：WSL2 Linux（moon 0.1.20261021 + 系统 sqlite3 dev + gcc + valgrind 3.18.1）

## 结果摘要

把「native 全量测试游走式 SIGSEGV/SIGABRT、探针 1/40 崩溃」从**概率现象**定位到**确定性缺陷**：

> `daqing/sqlite@0.4.0` 的 native stub 把 `sqlite3_stmt*` / `sqlite3*` **裸指针直接当 MoonBit GC 对象**回传；
> `Statement::finalize()` 里 `sqlite3_finalize` 已经把该内存 free 掉，而 MoonBit 运行时随后仍对它执行
> `moonbit_drop_object` ⇒ **use-after-free 写坏堆元数据**。

与 mizchi 时代 BUG-133 是**同一族**（那次是 stub 缺 `moonbit_make_external_object`）⇒ 换依赖没有换掉这类缺陷。

## 证据（valgrind，首条错误完整栈）

```
Invalid read of size 4
   at moonbit_drop_object (runtime.c:545)
   by ??? (main.mbt:19)                         ← 语句作用域结束，运行时 drop 该对象
Address 0x4d0b770 is 0 bytes inside a block of size 312 free'd
   at free
   by sqlite3_free
   by sqlite3VdbeFinalize
   by sqlite3_finalize
   by sqlite_finalize (stub.c:106)               ← daqing stub 的 finalize
   by ??? (sqlite_native.mbt:575)                ← Statement::finalize
   by ??? (main.mbt:31)                          ← 探针显式 finalize()
Block was alloc'd at
   by sqlite3Malloc → sqlite3VdbeCreate → sqlite3_prepare_v2
   by sqlite_prepare (stub.c:96)                 ← daqing stub 把 C 指针直接回传
   by ??? (sqlite_native.mbt:384)
   by ??? (main.mbt:19)                          ← db.prepare(...)
```
紧随 `Invalid write of size 4 at moonbit_drop_object (runtime.c:549)`，进程 `free(): invalid size` → SIGABRT。

复现命令（WSL）：
```bash
# 探针源由 scripts/blackbox/e2e_native_heap_probe.py 的 write_probe() 生成
moon build --target native temp/native_heap_probe
valgrind --track-origins=yes --num-callers=25 \
  _build/native/debug/build/temp/native_heap_probe/native_heap_probe.exe
```

旁证（同一族）：`moon test --target native src/ops -j 1` 的 `ops.blackbox_test.exe` 崩溃点在用例间**游走**
（清 temp 前后 `pipeline_*` 可全过而 `watchdog *` 崩；同一 `pipeline_3_*` 分别给过 SIGSEGV 与 SIGABRT），
因为 UAF 污染的是堆元数据，**爆点取决于后续 malloc/free 轨迹**，不取决于具体用例。

## 资源消耗

- WSL 内安装 moon（0.1.20261021）+ valgrind；worktree 由 origin/master 切出（隔离，不碰主 checkout）。
- 探针 native 构建 + valgrind 单轮约数分钟；`src/ops` 二分约 10 轮 `moon test`。

## 任务分配记录

| 步骤 | 手段 | 结论 |
|---|---|---|
| 能否在崩溃平台复现 | WSL + moon + 系统 sqlite3 | 能（首次真跑即崩） |
| 二分定位用例 | `moon test -f <pattern>` 按用例过滤 | **游走式**，不可归因到用例 |
| 依赖侧是否也崩 | 探针 `--runs 40` | `crashes=1/40`（跨实现存在） |
| 精确机制 | valgrind 直跟可执行 | **UAF：finalize 后 GC 二次 drop** |

## 遗留风险

1. **native 后端不可用**：凡走 `prepare/finalize` 的路径都会踩（`src/store` 首当其冲）。
2. **CI 的 native 臂会长期红**，且 `--runs 12` 在约 2.5% 命中率下漏检 ~74% ⇒ 「门绿」不可当「已修」。
3. 该缺陷在依赖侧，本仓不能单方面绕开（除非完全弃用 `Statement::finalize` 语义）。
4. 账本（`memory/bugs.md`）当前被并发 lane 反复重写，本轮报告条目的编号多次被复用/覆盖 —— 故结论落在本文件。

## 后续建议

1. **首选**：给 daqing 增加与 `patches/sqlite-bug133/stub.c` 同构的补丁——stub 侧用
   `moonbit_make_external_object(finalizer, size)` 包装指针，**释放交给 GC finalizer**，MoonBit 侧不再显式
   `sqlite3_finalize`；配套 `reapply` 后置校验（`.mooncakes` 会被 `moon update` 重生成，BUG-133 当年就是这么收口的）。
2. 过渡期最低成本：把探针 `--runs` 由 12 提到 60–100（漏检 22%→8%），让「门绿」有意义；属判据灵敏度决策。
3. 在 native 修好前，**权威门槛维持 JS 后端**；不要把 native 数写进任何「双端全绿」措辞。
4. 复检点：修好后用 `valgrind --error-exitcode=99` 跑探针一轮，**必须 0 error**（比「跑 N 次没崩」强得多）。

## 超额内容

- 顺带确认工作区指令里另一条根因修正：本机 `moon test --target js` 的
  `Unterminated string in JSON` 并非 moon 长路径缺陷，而是 **PATH 上的 `node.cmd` 垫片吞引号**；
  仓内已有常驻入口 `scripts/moon_test_env.py`（实测 1387/1387）。**此前多轮把它归因为 `\\?\` 长路径是错的**，
  本报告一并纠正：那是环境垫片问题，与 worktree 无关。

## 来源

- valgrind 原始日志：WSL `/tmp/vg2.log`（本轮会话产出）
- 探针：`scripts/blackbox/e2e_native_heap_probe.py`（本轮已修正归因文案与「换后端即安全」的错误假设）
- 账本：BUG-133（原件）、本轮条目因账本重写未能稳定落号
