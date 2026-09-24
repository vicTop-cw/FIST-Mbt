#!/usr/bin/env python3
"""score_gate.py —— fist-mbt 4-AI 概率自评分门禁 runner（全档达标 AND 聚合）。

用途
----
按固定顺序驱动 4 个评分 AI，各自对同一证据快照 + 统一 rubric 打分，逐档与目标
概率比较，AND 聚合后输出 PASS=是/否。用于确认「获奖概率是否达到目标」，
任一 AI 不通过或不可用则本轮 PASS=否（如实上报，不伪造通过）。

四大 AI
----
    AI1  你自身（本会话 agent）             —— 由外层通过 --ai1-json 注入 {p1,p2,p3,verdict}
    AI2  atomcode CLI · LongCat             —— 命令模板（默认 `atomcode -p {PROMPT}`）
    AI3  atomcode CLI · 默认模型            —— 命令模板（默认 `atomcode -p {PROMPT}`）；
          （注：AI3 曾为 codearts/盘古 并已弃用，现改由 atomcode 默认模型承担；
           如需换命令行，用 env `SCORE_AI3_CMD` 覆盖）
    AI4  atomcode CLI · kimi-k3             —— 命令模板（默认 `atomcode -p {PROMPT}`）

命令注入（无硬编码盘符）
----
    SCORE_AI2_CMD / SCORE_AI3_CMD / SCORE_AI4_CMD
    模板中可含 `{PROMPT}`（替换为组装好的完整提示词字符串）或
    `{PROMPT_FILE}`（替换为临时提示词文件路径）。默认模板用 `{PROMPT}`。

从每个 CLI 的 stdout 中抓取形如：
    SCORE_JSON:{"p1":0.xx,"p2":0.xx,"p3":0.xx,"verdict":"pass"|"fail","reason":"..."}

聚合口径（全档达标 AND）
----
    pass = all( ai['verdict']=='pass' and ai['p1']>=0.60 and ai['p2']>=0.80
                and ai['p3']>=0.95 for ai in [AI1,AI2,AI3,AI4] )
    任一 AI 解析失败 / 缺 p / CLI 不可用 → 该 AI 记 error，不降级为 pass。

用法示例
----
    python scripts/score_gate.py \\
        --evidence memory/research/_snapshot.md \\
        --ai1-json '{"p1":0.9,"p2":0.9,"p3":0.95,"verdict":"pass"}'

退出码：0=PASS，1=FAIL 或任一 AI error。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

# 统一 rubric 提示词：默认取本脚本同目录下的 _ai_prompt.md（相对定位，无硬编码盘符）
DEFAULT_RUBRIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_ai_prompt.md")

# 全档达标阈值（客观判据，与 _ai_prompt.md / spec §2.1 一致）
# 目标提档：一等 70% / 二等 85% / 三等 97%（2026-09-24 用户 /goal 更新）
THRESH = {"p1": 0.70, "p2": 0.85, "p3": 0.97}

# 目标概率（用于输出判读）
TARGET = {"p1": 0.70, "p2": 0.85, "p3": 0.97}

# AI2/AI3/AI4 命令模板默认值（相对占位；可用环境变量覆盖，杜绝绝对路径）
DEFAULT_CMDS = {
    "AI2": "{atomcode} -p \"{PROMPT}\"",
    "AI3": "{atomcode} -p \"{PROMPT}\"",  # 原为 codearts/盘古，已改 atomcode 默认模型
    "AI4": "{atomcode} -p \"{PROMPT}\"",
}


def build_prompt(rubric_text: str, evidence_text: str) -> str:
    """组装喂给每个 AI 的完整提示词：rubric + 证据快照内容。"""
    return (
        rubric_text
        + "\n\n## 证据快照（本次打分唯一事实依据）\n\n"
        + evidence_text
        + "\n\n请严格按 rubric 的「规定输出」返回，首行必须以 `SCORE_JSON:` 开头并输出唯一一行 JSON。"
    )


def _inflate_template(template: str, prompt: str, prompt_file: str) -> str:
    """把命令模板中的 {PROMPT}/{PROMPT_FILE} 占位符替换为实际内容/路径。"""
    if "{PROMPT_FILE}" in template:
        return template.replace("{PROMPT_FILE}", prompt_file)
    # 说明：{PROMPT} 为跨行的长提示词，用 shlex.quote 作 shell 安全包裹
    return template.replace("{PROMPT}", shlex.quote(prompt))


def extract_score_json(stdout: str):
    """从 stdout 中抓取第一个 SCORE_JSON:{...} 并解析；失败返回 None。"""
    if not stdout:
        return None
    m = re.search(r"SCORE_JSON:\s*(\{.*?\})\s*", stdout, flags=re.S)
    if not m:
        return None
    try:
        data = json.loads(m.group(1))
    except json.JSONDecodeError:
        return None
    return data


def run_cli(cmd: str, timeout: int):
    """执行一条 CLI 命令，返回 (exit_code, stdout, stderr)。

    不可用（找不到命令 / 超时 / 非零退出）时如实向上抛，由调用方判为 error。
    CLI 未安装等场景由本函数捕获并返回 (None, msg, "")，不使进程崩溃。
    """
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return None, "UNAVAILABLE: CLI not found", ""
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return None, f"UNAVAILABLE: timeout after {timeout}s\n" + out, ""
    except OSError as e:
        return None, f"UNAVAILABLE: {e}", ""


def gate(builder, ai1_json: dict, evidence_text: str, timeout: int):
    """顺序驱动 AI1..AI4 打分并 AND 聚合。返回 (rows, overall_pass)。"""
    # AI1：由外层注入，直取
    ai1_ok = isinstance(ai1_json, dict) and all(
        isinstance(ai1_json.get(k), (int, float)) for k in ("p1", "p2", "p3")
    )
    ai1 = {
        "name": "AI1",
        "carrier": "self 会话",
        "p": {k: ai1_json.get(k) for k in ("p1", "p2", "p3")} if ai1_ok else {},
        "verdict": ai1_json.get("verdict") if ai1_ok else None,
        "v": ai1_ok
        and (ai1_json.get("verdict") == "pass")
        and all(float(ai1_json.get(k, 0)) >= THRESH[k] for k in THRESH),
        "error": None if ai1_ok else "AI1: 缺 p 或非法输入",
    }

    rows = [ai1]
    rubric_text = open(builder.rubric_path, encoding="utf-8").read()
    prompt = build_prompt(rubric_text, evidence_text)

    for key, default_tmpl in DEFAULT_CMDS.items():
        tmpl = os.environ.get(
            {"AI2": "SCORE_AI2_CMD", "AI3": "SCORE_AI3_CMD", "AI4": "SCORE_AI4_CMD"}[key],
            default_tmpl,
        )
        with tempfile.NamedTemporaryFile("w+", suffix=".txt", encoding="utf-8", delete=False) as tf:
            tf.write(prompt)
            prompt_file = tf.name

        try:
            full_cmd = _inflate_template(tmpl, prompt, prompt_file)
            rc, out, err = run_cli(full_cmd, timeout)
        finally:
            try:
                os.unlink(prompt_file)
            except OSError:
                pass

        score = None
        error = None
        if rc is None:
            error = out.strip()[:200]  # UNAVAILABLE ...
        else:
            score = extract_score_json(out)
            if score is None:
                error = f"AI 输出未含可解析 SCORE_JSON（rc={rc}）。stdout 首 200 字：{out[:200]!r}"
            elif not all(isinstance(score.get(k), (int, float)) for k in ("p1", "p2", "p3")):
                error = "AI 输出缺 p1/p2/p3"

        if error:
            rows.append({
                "name": key,
                "carrier": {"AI2": "atomcode·LongCat", "AI3": "atomcode·默认", "AI4": "atomcode·kimi-k3"}[key],
                "p": {},
                "verdict": None,
                "v": False,
                "error": error,
            })
        else:
            ok = score["verdict"] == "pass" and all(float(score[k]) >= THRESH[k] for k in THRESH)
            rows.append({
                "name": key,
                "carrier": {"AI2": "atomcode·LongCat", "AI3": "atomcode·默认", "AI4": "atomcode·kimi-k3"}[key],
                "p": {k: score[k] for k in ("p1", "p2", "p3")},
                "verdict": score.get("verdict"),
                "v": bool(ok),
                "error": None,
            })

    overall = all(r["v"] and r["error"] is None for r in rows)
    return rows, overall


def render(rows, overall, target_text: str = ""):
    out = []
    out.append("== fist-mbt 4-AI 概率门禁 ==")
    header = f"{'AI':<5}{'载体':<18}{'verdict':<8}{'p1':>6}{'p2':>6}{'p3':>6}  error"
    out.append(header)
    out.append("-" * len(header))
    for r in rows:
        p = r["p"]
        out.append(
            f"{r['name']:<5}{r['carrier']:<18}"
            f"{(r['verdict'] or '-'):<8}"
            f"{p.get('p1', '-')!s:>6}{p.get('p2', '-')!s:>6}{p.get('p3', '-')!s:>6}  "
            f"{r['error'] or ''}"
        )
    out.append("-" * len(header))
    out.append("全档达标口径：p1>=0.70 && p2>=0.85 && p3>=0.97 才 pass；聚合=AND（全部 AI 通过才 PASS）。")
    out.append("PASS=是" if overall else "PASS=否")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="fist-mbt 4-AI 概率门禁 runner（AND 聚合，1 AI error 即 FAIL）")
    ap.add_argument("--evidence", required=True, help="证据快照文件路径（喂给所有 AI 的确凿事实）")
    ap.add_argument("--ai1-json", required=True, help="AI1 即指挥官自身打分 JSON {p1,p2,p3,verdict}（不含 SCORE_JSON 前缀）")
    ap.add_argument("--rubric", default=DEFAULT_RUBRIC, help="统一 rubric 提示词文件（默认同目录 _ai_prompt.md）")
    ap.add_argument("--timeout", type=int, default=180, help="每个 CLI 超时秒数（默认 180）")
    args = ap.parse_args(argv)

    builder = argparse.Namespace(rubric_path=args.rubric)

    with open(args.evidence, encoding="utf-8") as f:
        evidence_text = f.read()

    try:
        ai1_json = json.loads(args.ai1_json)
    except json.JSONDecodeError:
        ai1_json = {}

    rows, overall = gate(builder, ai1_json, evidence_text, args.timeout)
    print(render(rows, overall))
    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())