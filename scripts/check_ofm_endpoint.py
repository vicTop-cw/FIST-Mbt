#!/usr/bin/env python3
"""scripts/check_ofm_endpoint.py — OFM 端点入库探活判据（BUG-537）。

背景：OFM 端点/密钥按纪律 env-only 不入库，但「无入库判据」导致端点失效只能静默发生
（旧端点 18899 已实际失效过一次，现行 relay 端点 18326，见
reports/2026-10-31-ofm-relay-fullchain-report.md）。本判据只做一件事：
探 `{FIST_OFM_ENDPOINT}/v1/models`，按 HTTP 状态分类报告。

退出码契约（与本仓判据族同口径）：
  0 = 探活成功（200，端点在线）
  1 = 端点不可达 / 非预期状态（有 env 却探不通 ⇒ 这是缺陷面，必须红）
  2 = 判据无法自证（401=未鉴权属于「配置问题」不是端点死活问题 ⇒ 不判红不判绿，
      与「无 env SKIP」同档；另外判据自身异常也走本档，绝不冒用 1）
  3 = SKIP：FIST_OFM_ENDPOINT 未设置（不判红不判绿，判据无法出数绝不报绿）

argparse 天生拒绝未知参数（判例 R207 族硬要求）。
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ENV_ENDPOINT = "FIST_OFM_ENDPOINT"


def build_models_url(endpoint):
    """endpoint -> {base}/v1/models（去尾斜杠，容忍 base 带不带 /v1）。"""
    base = endpoint.rstrip("/")
    if base.endswith("/v1"):
        base = base[: -len("/v1")]
    return base + "/v1/models"


def classify_status(code):
    """HTTP 状态 -> 档位：ok / unauthorized / down / unexpected。"""
    if code == 200:
        return "ok"
    if code == 401 or code == 403:
        return "unauthorized"
    if code == 404 or 500 <= code < 600:
        return "down"
    return "unexpected"


def probe(url, timeout, opener=None):
    """真探一发。返回 (档位, 读数描述)。网络异常归 down（有 env 探不通就是缺陷面）。"""
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with (opener or urllib.request.build_opener()).open(req, timeout=timeout) as resp:
            return classify_status(resp.getcode()), "HTTP %s" % resp.getcode()
    except urllib.error.HTTPError as e:
        return classify_status(e.code), "HTTP %s" % e.code
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return "down", "unreachable: %s" % (e,)
    except Exception as e:  # 判据自身异常不许冒用 1
        return "error", "judge-fault: %r" % (e,)


def selftest():
    """变异对照（判例-29/30）：改坏被测机制，断言锁必须红；钉的是纯函数实现路径。"""
    checks = []
    # 正向
    checks.append(("build_url basic", build_models_url("http://127.0.0.1:18326")
                   == "http://127.0.0.1:18326/v1/models"))
    checks.append(("build_url trailing slash", build_models_url("http://h:1/")
                   == "http://h:1/v1/models"))
    checks.append(("build_url strip /v1", build_models_url("http://h:1/v1")
                   == "http://h:1/v1/models"))
    # 变异对照 M1：把 build_models_url 换成「不摘 /v1 的错实现」必须被抓住
    m1 = (lambda ep: ep.rstrip("/") + "/v1/models")("http://h:1/v1")
    checks.append(("M1 build_url mutation detected", m1 != build_models_url("http://h:1/v1")))
    # 变异对照 M2：classify 把 500 误判成 ok 必须被抓住
    checks.append(("M2 classify 500 not ok", classify_status(500) != "ok"))
    checks.append(("classify 200 ok", classify_status(200) == "ok"))
    checks.append(("classify 401 unauthorized", classify_status(401) == "unauthorized"))
    checks.append(("classify 404 down", classify_status(404) == "down"))
    # 退出码映射锁：ok->0 / down->1 / unauthorized&error->2 / skip->3
    checks.append(("rc map", [RC_OF[k] for k in ("ok", "down", "unauthorized", "error", "skip")]
                   == [0, 1, 2, 2, 3]))
    # CALLFACE（check_selftest_call_face J2）：从 selftest 出发的调用图要够得着
    # 调用面锚点（main）。合成 argv 走「argparse 拒未知旗标」档——argparse 天生即拒
    # （SystemExit 2），解析发生在一切 IO 之前 ⇒ 不碰真仓、不起网络（hermetic 干净）。
    try:
        main(["--definitely-not-real"])
        face_got = None
    except SystemExit as e:
        face_got = e.code
    checks.append(("callface main rejects unknown flag rc=2", face_got == 2))
    bad = [name for name, ok in checks if not ok]
    if bad:
        print("SELFTEST FAIL: %s" % ", ".join(bad))
        return 2
    print("SELFTEST OK: %d checks (2 mutation controls)" % len(checks))
    return 0


RC_OF = {"ok": 0, "down": 1, "unauthorized": 2, "error": 2, "skip": 3}


def main(argv=None):
    ap = argparse.ArgumentParser(description="OFM endpoint liveness probe (BUG-537)")
    ap.add_argument("--selftest", action="store_true", help="run pure-function selftest")
    ap.add_argument("--timeout", type=float, default=5.0, help="probe timeout seconds")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    endpoint = os.environ.get(ENV_ENDPOINT, "")
    if not endpoint:
        print("SKIP: %s not set — 探活判据无法出数，不判红不判绿" % ENV_ENDPOINT)
        return 3

    url = build_models_url(endpoint)
    tier, detail = probe(url, args.timeout)
    print("OFM probe %s -> %s (%s)" % (url, tier, detail))
    if tier == "ok":
        body = _peek_models(url, args.timeout)
        if body is not None:
            print("models: %s" % body)
        return 0
    return RC_OF[tier]


def _peek_models(url, timeout):
    """成功时顺带打印模型数（只读，失败不影响结论）。"""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        return "%d models" % len(data.get("data", []))
    except Exception:
        return None


if __name__ == "__main__":
    sys.exit(main())
