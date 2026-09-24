#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/laya_decide.py — Laya 决策 sidecar（fist-mbt 可选外部决策工具）

把 LH调 python ML 模型 Laya 包成一个可被 fist-mbt MCP server 调用的 JSON sidecar。
fist-mbt 通过 node child_process spawn 调用本脚本，实现"自动探测 laya 是否可用，
可用就快速分类、不可用就降级（unavailable），不影响现网功能"。

用法：
    python scripts/laya_decide.py --probe        # 探测：退出码 0=可用, 3=不可用
    python scripts/laya_decide.py                # 从 stdin 读 JSON，输出决策 JSON

stdin 输入（单行 JSON）：
    {
      "context": "任务描述/待决策文本",
      "questions": { ... 可选，缺省用 laya.router_questions() 的标准 schema ... },
      "model": "english"   // 可选，Router default 模型
    }

stdout 输出（成功时）：
    {
      "available": true,
      "answers": { <question_name>: <value>, ... },
      "auto_decide": true/false,
      "escalate": true/false
    }

退出码约定：
    0  成功（含 available:false 但脚本能判断无 laya 时能否正常被调用）
    1  运行期异常（stderr 有详情）
    3  Laya 不可用（--probe 探测时明确返回）

设计要点：全程无 LLM、只输出结构化 JSON；失败即安全退出，绝不 panic。
"""
import json
import sys

_RET_OK = 0
_RET_ERR = 1
_RET_UNAVAILABLE = 3


def _json_compact(obj):
    """确保 JSON 可被 size = 紧凑序列化（default=str 兜底）。"""
    return json.dumps(obj, ensure_ascii=False, default=str)


def _probe():
    """探测 Laya 是否可用。退出码 0=可用，3=不可用，1=异常。"""
    try:
        import laya  # noqa: F401
    except Exception:
        sys.exit(_RET_UNAVAILABLE)
    try:
        from laya import Router  # noqa: F401
    except Exception:
        sys.exit(_RET_UNAVAILABLE)
    sys.exit(_RET_OK)


def _normalize_answers(answers):
    """把 predict 返回的 answers 规范化成简单 JSON（剔除不可序列化/嵌套噪音）。"""
    out = {}
    if not isinstance(answers, dict):
        return {"_raw": _json_compact(answers)}
    for k, v in answers.items():
        if isinstance(v, dict):
            # 例如 {choice: "code", confidence: 0.93}
            out[k] = v
        elif isinstance(v, (str, int, float, bool)) or v is None:
            out[k] = v
        else:
            out[k] = _json_compact(v)
    return out


def _decide():
    """从 stdin 读决策请求，调用 Laya Router.predict，输出决策 JSON。"""
    try:
        raw = sys.stdin.read()
        req = json.loads(raw) if raw.strip() else {}
    except Exception as e:
        sys.stderr.write(f"bad input: {e}\n")
        sys.exit(_RET_ERR)

    context = req.get("context", "")
    if not context:
        sys.stderr.write("missing context\n")
        sys.exit(_RET_ERR)

    questions = req.get("questions")
    model = req.get("model", "english")

    try:
        from laya import Router
        from laya import router_questions
    except Exception as e:
        # Laya import 失败 → 视作不可用，输出降级 JSON（退出码 0，让调用方读到 available=false）
        print(_json_compact({"available": False,
                             "reason": f"laya not importable: {e}"}))
        sys.exit(_RET_OK)

    try:
        if questions is None or not isinstance(questions, dict):
            questions = router_questions()
        router = Router(default=model)
        result = router.predict(context, questions)
        answers = result.get("answers", result) if isinstance(result, dict) else result
        normalized = _normalize_answers(answers)
        # auto_decide / escalate 启发式：
        #   - auto_decide: 若所有 answer 都能取到、无 need 人工审核迹象，则 true
        escalate = False
        for v in normalized.values():
            if isinstance(v, dict):
                # 显式 needs_review 信号（人工审核）→ escalate
                if v.get("needs_review"):
                    escalate = True
                    continue
                conf = v.get("confidence", 1.0)
                try:
                    conf = float(conf)
                except (TypeError, ValueError):
                    conf = 1.0
                # 低置信度 → escalate
                if conf < 0.6:
                    escalate = True
        auto_decide = (not escalate)
        print(_json_compact({
            "available": True,
            "answers": normalized,
            "auto_decide": auto_decide,
            "escalate": escalate,
        }))
        sys.exit(_RET_OK)
    except Exception as e:
        sys.stderr.write(f"predict failed: {e}\n")
        sys.exit(_RET_ERR)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--probe":
        _probe()
    _decide()


if __name__ == "__main__":
    main()