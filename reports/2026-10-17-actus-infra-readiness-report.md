---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_3abac07aca3611f18b7f525400393706
    ReservedCode1: 4qVbF/wZb5ZVtSCuznDygadd4pSQ0158MMlc+JmsDVME4nYhqjEWr2jsGHaXzSddJZbd6fVHPc3mQx28ig3tjdpQGqrtcHfsTyrZNYgyZ55wZAJZ5TNLFI3satPgjpUX/mCL/S0i2U+/3BYzFtemu8PUSrxTRr1IPWqCyiA/c2fg9WvBkMxXAMXwC48=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_3abac07aca3611f18b7f525400393706
    ReservedCode2: 4qVbF/wZb5ZVtSCuznDygadd4pSQ0158MMlc+JmsDVME4nYhqjEWr2jsGHaXzSddJZbd6fVHPc3mQx28ig3tjdpQGqrtcHfsTyrZNYgyZ55wZAJZ5TNLFI3satPgjpUX/mCL/S0i2U+/3BYzFtemu8PUSrxTRr1IPWqCyiA/c2fg9WvBkMxXAMXwC48=
---

# actus 项目基建完备度报告

- **任务**：T0（namespace `actus-basic`）——核查 actus 项目基建进展：盘点 docs/engine/contracts/actions/tests/README 等基建现状，输出基建完备度报告
- **核查日期**：2026-10-17
- **核查对象**：`E:\IDEProjects\AI\actus`（remote：git@atomgit.com:VictorTop/actus.git，master）
- **执行者**：atomcode-fist-exec（FIST 指挥官模式，本人核查 + 子任务分派留痕）

---

## 一、结果摘要

**总评：基建完备度高（约 85%），文档/测试/CI/依赖声明四大件齐全且口径互相咬合；主要缺口是打包面（无 pyproject.toml）与根目录临时文件卫生。**

| 维度 | 状态 | 要点 |
|---|---|---|
| 文档 | ✅ 就绪 | docs/ 44 份（01~45 编号族 + DEVELOPMENT_STANDARDS + 快速上手 + semver），README.md/README_EN.md 双语，CHANGELOG.md（100KB），CONTRIBUTING.md，AGENTS.md（§5.2 权威测试口径，2026-10-12 刚更新） |
| 许可 | ✅ 就绪 | LICENSE（Apache-2.0）+ LICENSE-COMMERCIAL.md + NOTICE 三件套，与 README 许可策略一致 |
| 引擎 | ✅ 就绪 | engine/actuscore 58 个模块（selfdrive/omega/trust/security/cost/evolution/selfheal 全特性覆盖），engine/actus CLI 入口（scan/validate/list/run/mcp/vault/scaffold… 帮助完整），engine/_meta/triggers.json |
| 契约 | ✅ 就绪 | contracts/ 4 份 JSON Schema（action/adapter/cloud/policy），CI 中有对应 schema-check 校验步 |
| 动作库 | ✅ 就绪 | actions/ 113 个 `.actus.md`（adapters/cli/demo/ecosystem/system/automation 等族），含签名样例（.sig） |
| 测试 | ✅ 就绪 | tests/ 113 个测试文件（单测+e2e+契约+回归），pytest.ini 带 120s/条超时护栏（pytest-timeout），AGENTS.md §5.2 钉死"五根 PYTHONPATH + run_tests.ps1"权威口径（旧 `PYTHONPATH=engine` 跑法已判错并文档化） |
| CI | ✅ 就绪（单点） | 真实执行者 = `.gitcode/workflows/ci.yml`（AtomGit/GitCode runner，validate+test 两 job）；`.github/workflows/ci.yml` 与 `.gitlab-ci.yml` 为同构镜像/备用（头部注释明确声明未镜像不执行），三处测试口径同源 requirements*.txt |
| 依赖声明 | ✅ 就绪 | requirements.txt（运行面：vools[actus]>=0.7.9、jsonschema、pyyaml、paramiko>=4.0.0，下限理由逐条注释）+ requirements-dev.txt（vools[all]>=0.7.8、pytest、pytest-timeout>=2.4、fastapi/httpx，隐性依赖已显式化） |
| 构建脚本 | ✅ 就绪 | run_tests.ps1（解释器自动解析，2026-10-12 修掉了钉死绝对路径的坑）、install.ps1（一键安装 4 步检查）、register-actus.ps1、scripts/fist_board.ps1 / fist_mbt.ps1 |

## 二、缺失与风险（按优先级）

| # | 缺口 | 严重度 | 证据 |
|---|---|---|---|
| 1 | **打包面缺失**：根目录与 engine/ 均无 pyproject.toml/setup.py/setup.cfg，项目本体无法 pip install/版本化分发 | 中 | `ls engine/pyproject.toml engine/setup.py` 全部 No such file；requirements 注释显示 vools-actus 已上 PyPI 而 actus 本体没有对应发行面 |
| 2 | **CI 实际运行状态未证实**：真实 CI 只在 `.gitcode/workflows/ci.yml`，其注释自述「代码化流水线能力需开通，未开通时提交本文件不产生流水线运行」——本次核查只确认文件存在与形状，未能确认线上有绿运行 | 中 | `.gitcode/workflows/ci.yml` 头部注释；仓库只有 AtomGit 一个 remote |
| 3 | **根目录卫生**：约 15 个临时面文件未跟踪且未忽略（_p2_*.py × 8、_tmp_*.py、tmp_*.txt、_draft_*.md × 3、_fist_doctor_check.db、_alias_probe.py、_tpl_sig.py、_proxy_probe.py、_temp_validate_all.py 等，git status ?? 抽样可见）；另有 monitorclip.sh、test_upload.txt 被 git 跟踪（后者明显是临时件） | 低 | `git check-ignore` 抽样仅命中 fist-mbt.db；`git ls-files` 命中 monitorclip.sh/test_upload.txt |
| 4 | 无 Makefile / run_tests.sh：统一入口 run_tests.ps1 仅 Windows；Linux 侧靠 CI 里手工拼五根 PYTHONPATH 等效，本地 Linux 开发者无现成入口 | 低 | .gitlab-ci.yml test job 手工拼 PYTHONPATH_TEST |
| 5 | 无 .editorconfig / Dockerfile：非必需，仅记录 | 低 | 顶层文件存在性盘点 |

## 三、下一步建议

1. **（owner 决策，5 分钟）**登录 AtomGit/GitCode 仓库页面确认「流水线/Actions」有近期运行条目；若无，按 `.gitcode/workflows/ci.yml` 注释口径联系客服开通代码化流水线——否则"CI 必须绿"实为无人执行。
2. **补 pyproject.toml**：哪怕先只做 wheel 元数据（name/version/依赖引用 requirements.txt），打通 actus 本体的安装与版本化，也消掉与 vools-actus 的分发落差。
3. **根目录清场**：_p2_*/tmp_*/_draft_* 一类移入 archive/（或加 .gitignore 规则），test_upload.txt 出库；一次 commit 收口，防临时面继续漂移。
4. **（可选）**镜像 run_tests.sh 给 Linux 开发者（复用 CI 里已验证的五根 PYTHONPATH 拼法）。

## 四、任务分配记录（FIST 流程留痕）

| 步骤 | 动作 | 结果 |
|---|---|---|
| claim | T0 → atomcode-fist-exec | ✅ 已领取 |
| plan | T0 → T0.1 / T0.2 / T0.3 | ✅ 拆分 3 叶 |
| execute+submit+verify | T0.1 文档与规范面 / T0.2 引擎·契约·动作库 / T0.3 测试·CI·依赖·构建面（本人核查后逐叶交付） | ✅ 3/3 通过 |
| verify+archive | T0 整体 | ✅（见任务库状态） |

- **资源消耗**：FIST CLI 调用约 15 次（store_open/list/claim/plan/get/execute/submit/verify/archive）；对 actus 仓库只读盘点 6 轮 bash（find/ls/git 查询），零写入 actus 仓库。
- **报告落盘**：本文件（FIST-Mbt 侧 reports/，符合本仓汇报规范；actus 仓库未写入任何文件）。
- **超额内容**：无（核查范围与 T0 描述一致）。
- **来源**：actus 仓库实况（文件存在性、CI 配置正文、AGENTS.md §5.2、requirements 注释、git ls-files/check-ignore/status 实测），无推测项；不确定处（CI 线上运行状态）已按"未证实"如实标注而非假定绿。
*（内容由AI生成，仅供参考）*
