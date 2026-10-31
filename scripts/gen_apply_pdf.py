#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_apply_pdf.py —— 生成一页《项目申报书》PDF（A4 纵向，fpdf2 + simhei.ttf）。
用法: python scripts/gen_apply_pdf.py [out.pdf]
输出默认: <repo root>/项目申报书.pdf  （个人参赛件，不入 git）
无需联网；字体取系统 simhei.ttf，缺失时回退为 A4 横向纯文本占位并提示。
"""

# BUG-138 残余面：Windows 默认 cp936 控制台下，中文结论一红就崩在 print 里，
# traceback + rc=1 会被读成「缺陷在场」那一档——那是尺子自己坏了。先把两条流钉 UTF-8。
import sys as _sys
if hasattr(_sys.stdout, "reconfigure"):
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(_sys.stderr, "reconfigure"):
    _sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import os
import sys

from fpdf import FPDF

ROOT = os.path.dirname(os.path.abspath(__file__)) + os.sep + ".."
ROOT = os.path.normpath(ROOT)
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "项目申报书.pdf")


def find_font():
    for p in (
        r"C:\Windows\Fonts\simhei.ttf",
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simsun.ttc",
    ):
        if os.path.exists(p):
            return p
    return None


class Pdf(FPDF):
    def __init__(self):
        super().__init__(format="A4")
        font = find_font()
        self.add_font("cjk", "", font or os.path.join(ROOT, "scripts", "_dummy.ttf"))
        if font:  # 允许 bold 样式复用同一字体文件（fpdf2 按 族+样式 查字体）
            self.add_font("cjk", "B", font)
            self.add_font("cjk", "I", font)
        self._has_font = font is not None
        self.set_auto_page_break(auto=False)
        self.set_margins(10, 8, 10)
        self.set_y(8)

    def hd(self, txt, size=11, bold=False):
        if not txt:
            self.ln(1.2)
            return
        self.set_font("cjk", "B" if bold else "", size)
        self.set_text_color(20, 20, 20)
        self.set_x(self.l_margin)
        self.multi_cell(0, size * 0.42, txt, new_x="LMARGIN", new_y="NEXT")

    def sec(self, txt):
        self.set_font("cjk", "B", 10)
        self.set_text_color(8, 60, 120)
        self.cell(0, 5, txt, new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(8, 60, 120)
        self.set_line_width(0.4)
        y = self.get_y()
        self.line(10, y, 200, y)

    def p(self, txt, size=8.5):
        self.set_font("cjk", "", size)
        self.set_text_color(30, 30, 30)
        self.set_x(self.l_margin)
        self.multi_cell(0, size * 0.44, txt, new_x="LMARGIN", new_y="NEXT")

    def table(self, rows, colw):
        for i, r in enumerate(rows):
            x = 10
            for j, cell in enumerate(r):
                self.set_font("cjk", "B" if i == 0 else "", 8)
                self.set_text_color(30, 30, 30)
                if i == 0:
                    self.set_fill_color(8, 60, 120)
                    self.set_text_color(255, 255, 255)
                else:
                    self.set_fill_color(245, 245, 250)
                fill = False
                self.set_xy(x, self.get_y())
                self.cell(colw[j], 4.6, cell, border=0, fill=(i == 0))
                x += colw[j]
            self.ln(4.6)


def main():
    pdf = Pdf()
    pdf.add_page()
    pdf.hd("FIST-Mbt 项目申报书", 15, True)
    pdf.hd("FIST 指挥官任务分配体系的纯 MoonBit 原生重写与 MCP 化", 9)
    pdf.hd("v0.3.10 · 已发布 mooncakes.io/fist-mbt + GitHub Release · 182 MCP 工具 · 2002 测试全绿 · JS 为权威门槛", 8)

    pdf.sec("一、项目简介")
    pdf.p("把多智能体任务编排框架 FIST（原 Python 版）用纯 MoonBit 原生重写，封装为 MCP Server。"
          "任何 MCP 客户端（Claude Desktop / AtomCode / Cursor / 自研 JSON-RPC 客户端）均可经标准协议调用 182 个工具，"
          "完成任务的发布 / 认领 / 拆分 / 执行 / 验收 / 归档全生命周期。")

    pdf.sec("二、方向与通用性")
    pdf.p("方向：MCP Server / 多智能体任务编排 / AI 基础设施。三层解耦（协议层 MCP → 引擎层 状态机+DAG → 执行层 可替换 Executor），"
          "不绑定任何模型/领域；多租户命名空间**物理**隔离到独立 SQLite（交互与无人值守路径同过 engine_for_ns 一道路由门，非法 ns 直接拒、不静默回落主库）。")

    pdf.sec("三、核心能力")
    pdf.table(
        [("模块", "能力", "工具"),
         ("生命周期", "九态状态机 · 父任务上卷 · K 值递归衰减 · 非法迁移拦截", "12"),
         ("DAG 依赖", "关键路径 · 并行度 · 拓扑排序 · 依赖检查 · ASCII 可视化 · 环闸唯一真源 depend_edge_ok（三条写边入口全过）", "6"),
         ("智能调度", "L1-L4 自适应分级 · 成本档路由 · 执行器抽象", "3+"),
         ("Omega 验证", "spec 一票否决 · 验收门 omega_archive_gate 覆盖 execute/verify/archive/force/自动续轮 · 自动修复真三轮（逐轮在上轮产物上收敛，未知根因不重盖章）", "2"),
         ("运维治理", "冲突检测 · 心跳 · 超时回滚 · 归档清理 · 审计权限", "5"),
         ("多租户", "命名空间物理隔离 SQLite（含自驱/看护/report_bug 等无人值守写路径）· 惰性开关 · scratch 临时区", "3"),
         ("自进化/自驱", "memory_consolidate · evolve_distill · 审视-拆解-发布 自收敛", "8")],
        [38, 112, 14])

    pdf.sec("四、应用场景")
    pdf.p("AI 编程任务编排：对话驱动发布根任务→自动拆分子任务→分发并行执行→验收上卷；"
          "多项目并行：按命名空间隔离数据并用 cost_stats 汇总；"
          "自愈运维：heartbeat 心跳 + heal 超时回滚 + dag_ready 拓扑派发，避免任务卡死。")

    pdf.sec("五、质量与可复现")
    pdf.p("2002 项测试（`Total tests: 2002, passed: 2002, failed: 0`，判绿看汇总行不看退出码）覆盖全生命周期/DAG（含成环拒绝的盘上核对）/"
          "审计/并发/Omega（含验收门五条路径与自动修复三轮）。针对上轮拒收六项的**回归锁已入库**："
          "`src/engine/engine_acc_reject_wbtest.mbt`(7 格) + `src/omega/omega_acc_fix_test.mbt`(4) + "
          "`src/evidence/evidence_acc_fix_test.mbt`(2) + **独立包** `tests/external_executor/`(3)；"
          "克隆后一条命令复跑：`python scripts/moon_test_env.py --target js`。"
          "moon check 0 错误（48 条 warning 全部在 `docs/warning-ledger.md` 点名，覆盖率 100%）；~90 把 `check_*.py` 常驻守卫。"
          "另有一支**六格活体探针**（真起 server、真发工具调用、真读 sqlite，另带一格合成违例自证「尺子会红」）"
          "`scripts/blackbox/e2e_acceptance_recheck.py`，2026-10-31 本机读数 `A1 PASS / A2 PASS / A3 PASS / A4 SKIP / A5 PASS / A6 PASS / ST1 PASS`。"
          "**如实声明：该探针脚本本轮尚未进 git**——本仓纪律要求「脚本」与「它的电池登记面」必须同一笔提交，"
          "而登记面此刻被另一条并发车道的未提交改动占用（成因与执行法见 `reports/2026-10-31-hackathon-rejection-closure-report.md` §四.7）。"
          "**本轮另读 CI 原始回执实测抓出并修掉一项不在拒收单里的跨平台缺陷（BUG-507）**："
          "`.mbt` 放行规则的临时目录只认 `TEMP`/`TMPDIR`/`TMP`，ubuntu runner 三个都不给 → "
          "`mbt_include` 在 Linux 上恒 false、`Test (js)` 两格真红，而本机 Windows 永远测不出这一形；"
          "已抽成纯函数 `ocr_temp_candidates(env)` 加 POSIX `/tmp`、`/var/tmp` 兜底，锁三格 + 变异对照（清空兜底 → 3/3 红）。"
          "如实边界：native 轨未知子命令退出码仍为 0（js 轨为 2，账本 BUG-506 OPEN）；执行器注册表存名字与能力标签、"
          "不持有 trait 实例，远程沙箱接入需本地包装可执行文件（BUG-505 未锁的缺口）；"
          "测试总数现状面（README/AGENTS 等 10 份）仍写上一轮的 1983，同步动作与上述同一笔结转（§四.2）。")

    pdf.sec("六、性质 / 参考 / 仓库")
    pdf.p("移植项目（原 Python FIST → 纯 MoonBit，未搬运 Python 代码，Apache-2.0）。")
    pdf.p("参考：FIST（gitcode.com/VictorTop/FIST，Apache-2.0）；")
    pdf.p("仓库：github.com/vicTop-cw/FIST-Mbt（15+ 实质 commits）· 已发布 mooncakes.io/vicTop-cw/fist-mbt@0.2.4")

    if not pdf._has_font:
        print("WARNING: 未找到系统 CJK 字体，PDF 可能以占位渲染。", file=sys.stderr)
    pdf.output(OUT)
    print("PDF written:", OUT)


if __name__ == "__main__":
    main()
