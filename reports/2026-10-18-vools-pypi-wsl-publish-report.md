# vools PyPI 发布 + WSL Linux 接入测试 · 执行报告

- **任务**: FIST-Mbt T0（namespace: `vools-wsl-publish`）
- **执行者**: atomcode-publisher（AtomCode）
- **日期**: 2026-10-18
- **项目仓**: `E:\IDEProjects\AI\vools`（= `FIST-Mbt\_proj_vools` junction，同一仓库）

---

## 1. 结果摘要

vools 及两个有实质本地改动的子包（bridges / actus）已从 0.7.9 升级 **0.8.0** 并发布到 PyPI；
Windows 侧 wsl 修复验证与 WSL Ubuntu-22.04 Linux 侧冒烟全部通过。

| 包 | PyPI 旧版 | 本次发布 | PyPI 链接 |
|---|---|---|---|
| vools | 0.7.9 | **0.8.0** | https://pypi.org/project/vools/0.8.0/ |
| vools-bridges | 0.7.9 | **0.8.0** | https://pypi.org/project/vools-bridges/0.8.0/ |
| vools-actus | 0.7.9 | **0.8.0** | https://pypi.org/project/vools-actus/0.8.0/ |
| vools-rx / vools-dll32 / vools-xl / vools-pyk | 0.7.6 / 0.7.6 / 0.7.6 / 0.1.1 | 未发布（无本地新改动，按任务卡保持不变） | — |

## 2. 阶段 1 · 整理与提交

审查结论：wsl.py 超时修复（`subprocess.run(timeout)` → `_run_cmd_timeout` 杀整棵进程树）方向正确、
惰性 import 防循环依赖、返回形状兼容；actus/md 为配套功能扩展（probe 子命令、md.rich 模块化）。
发现并处理两处"源码面 ≠ 发布面"风险：`md/rich/` 子包（被已改代码引用但未跟踪）与 `bat/` 桥接包、
`actus/_proc.py` 一并入库。

**提交清单**（共 7 笔 + 1 合并，已推送 gitcode + github 双远端）:

| commit | 内容 |
|---|---|
| 9a25827 | fix(bridge.wsl): wsl_run/_probe_wsl 超时改用 _run_cmd_timeout 杀进程树（本任务核心修复） |
| 86d2351 | feat(md.rich): 富内容预览 scan/render 模块化 + --output/--serve/hot-reload |
| a6f7649 | feat(actus): probe 子命令 + intent ready 过滤 + AI 路由 |
| 81aefc6 | chore: 账本/审计/规划文档整理（BUG-81~84 全 FIXED） |
| cebcf36 | feat(bridge.bat): Windows 批处理语言桥接包 |
| c61d8d5 | Merge github/main（远端 workflow 演进版，add/add 冲突取宿主侧） |
| 1fa895a | fix(actus): dependency 改用 run_cmd_safe（新增 _proc.py） |
| c6efff0 | chore(release): 版本 bump 0.8.0（主包 + extras pin 同步） |

账本核对：BUG-1~84 中唯一 OPEN 为 **BUG-80**（py3.6 PEP 562 属性访问缺口），已有量化理由
登记为"刻意不修"（修了会引入稳定复现的套件回归），不阻塞本次发布。

## 3. 阶段 2 · 版本 bump / 构建 / 冒烟

- 版本点更新：`vools/__init__.py __version__`、`bridges/pyproject.toml version`、
  `actus/pyproject.toml version`、主包 extras 精确 pin（bridges/bridge-md/actus + all，共 5 处）。
  版本号唯一性发布前已核对：PyPI 三包 0.8.0 均为 HTTP 404（未占用）。
- `python -m build` 三包 sdist + wheel 全部构建成功。
- wheel 内容抽验：md/rich、bat、core/wsl.py 进 bridges wheel；_proc.py、ai/routing.py 进 actus wheel；
  `vools/lib/linux/*.so` 进主包 wheel；METADATA extras pin 正确。
- venv 隔离冒烟（离线装本地 wheel，extras 安装）：vools 0.8.0、wsl/md.rich/bat/_proc 全部可导入。

## 4. 阶段 3 · PyPI 发布与验证

- 方式：`python -m twine upload --non-interactive`，token 仅经环境变量注入
  （`TWINE_PASSWORD`，进程环境读取，未落盘未回显未提交）。
- 顺序：vools-bridges → vools-actus → vools（主包 extras 精确 pin 两个子包 0.8.0）。
  三包 **wheel + sdist** 均上传成功（见上表 PyPI 链接）。
- 验证：独立 venv 从 **PyPI 公网源** `pip install "vools[bridges,actus]==0.8.0"` 成功，
  三包版本 0.8.0，wsl/md.rich/_proc 可导入。

## 5. 阶段 4 · WSL 双端验证

### 5.1 Windows 侧（发布版 vools[bridges]==0.8.0，venv 隔离）

| 用例 | 结果 |
|---|---|
| `wsl_run(['echo','hello-from-vools-wsl-run'])` | PASS，rc=0，stdout 正确 |
| `wsl_run(['python3','--version'])` | PASS，rc=0，"Python 3.10.12" |
| `_probe_wsl(['echo','probe-ok'])` | PASS，(True, True) |
| 超时杀进程树：`wsl_run(['sleep','60'], timeout=5)` | PASS，rc=-9，实测 5.6s 按时返回（旧实现会挂住） |

### 5.2 Linux 侧（WSL Ubuntu-22.04，Python 3.10.12）

| 用例 | 结果 |
|---|---|
| `import vools`，`__version__ == "0.8.0"` | PASS |
| `vools.functional.pipe_ops`：`Ops.mean([1,2,3])` / `Ops.mean([])` | PASS（空序列除零修复生效，无 ZeroDivisionError） |
| `vools.curried.composition.memoize` 装饰器 | PASS，_sq(7)=49 |
| `vools.bridge.core.wsl`（wsl_run/_probe_wsl/resolve_command 属性） | PASS |
| `vools.bridge.md.rich`（scan_rich/render/RichConfig） | PASS |
| `vools.actus._proc.run_cmd_safe(['echo','proc-ok'])` | PASS，rc=0 |
| `vools/lib/linux/*.so` 随包分发 + ctypes dlopen | PASS，**6/6 全部加载成功** |

### 5.3 安装口径说明（如实记录）

WSL NAT 模式不镜像 Windows 的 localhost 代理（wsl 启动横幅明示），直连 PyPI 仅 ~27 kB/s，
bridges wheel（4.4 MB）两轮下载均超时失败。因此 Linux 侧安装采用 `pip install --no-index` 离线
安装 `/mnt/e` 上的本地发布 wheel；**等效性证据**：三个 wheel 的 sha256 与 PyPI 官方 JSON 返回的
digests 逐一核对全部 MATCH（vools / vools-bridges / vools-actus），即同一 artifact。
Windows 侧则为真实的 PyPI 公网源安装验证。此环境限制属 WSL 网络配置，非 vools 缺陷。

### 5.4 过程中的非包缺陷修正

冒烟脚本首版误写 `from vools.api import memoize`（真实路径 `vools.curried.composition.memoize`，
顶层为拼写不同的 `vools.memorize`）导致一次 ImportError——系测试脚本路径假设错误，已修正重跑，
与发布物无关。

## 6. 遗留风险与建议

1. **WSL PyPI 直连慢**：NAT 模式无代理镜像。建议后续在 `~/.wslconfig` 配 `networkingMode=mirrored`
   （Win11 22H2+）或在 WSL 内显式设代理，才能真正走公网源装包。
2. **BUG-80 仍 OPEN**：py3.6 PEP 562 缺口（pyk 懒加载），修复前置是"py3.6 import vools 连带拉起
   vools.pyk"的跨模块设计变更；包声明 requires-python>=3.6，若未来放弃 3.6 可直接关闭该条。
3. **vools-actus 的 deps pin**：actus 0.8.0 wheel 声明 `vools-bridges>=0.7.9`（范围 pin），与主包
   extras 的精确 pin 风格不一致；未动它（超出本任务授权面），建议下轮统一。
4. **github/main 曾被远端 workflow 提交分叉**：已合并（c61d8d5）并双侧推送对齐，同步 workflow 的
   add-only 语义未验证全链路（属宿主 CI 面，不在本任务范围）。

## 7. 交付物

- PyPI：vools 0.8.0 / vools-bridges 0.8.0 / vools-actus 0.8.0（wheel + sdist）
- 本仓报告：`reports/2026-10-18-vools-pypi-wsl-publish-report.md`
- FIST 记录：T0 claim → execute → submit（namespace `vools-wsl-publish`，库 `vools-wsl-publish.db`）

## 8. 来源

- 任务卡：T0 description（含阶段 1~5 步骤与硬性约束）
- 实测：本机 Windows 11 + WSL Ubuntu-22.04（Python 3.10.12）、PyPI JSON API sha256 核对、
  双 venv 冒烟输出（正文所引全部读数均来自实际执行，无自述推定）
