#!/usr/bin/env python3
"""scripts/fist-pr-automator.py - yaml -> PR -> gate -> merge pipeline.
Reads a PR definition yaml, runs local unified gate, pushes branch, opens
PR/MR via curl (GITHUB_TOKEN / GITCODE_TOKEN), waits gate green, merges.
rc: 0=ok 1=blocked 2=degraded. Pure ASCII, stdlib only."""
import json, os, re, subprocess, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
GH_API = "https://api.github.com"
GC_API = "https://gitcode.com/api/v5"

def run(cmd, cwd=None, env=None):
    e = dict(os.environ)
    if env: e.update(env)
    return subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True, encoding="utf-8", errors="replace")

def sh(cmd, cwd=None, env=None):
    r = run(cmd, cwd=cwd, env=env)
    if r.returncode:
        raise RuntimeError("cmd rc=%d %s: %s" % (r.returncode, cmd[0], (r.stderr or r.stdout).strip()[-200:]))
    return r.stdout.strip()

def parse_yaml(text):
    """Minimal yaml subset: top-level 'key: value' + one indented block per key."""
    d = {}; key = None; buf = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"): continue
        if line[:1] in (" ", "\t"):
            if key is not None: buf.append(line.strip())
            continue
        m = re.match(r"^([A-Za-z0-9_\-]+):\s*(.*)$", line)
        if not m: continue
        if key is not None and buf: d[key] = "\n".join(buf); buf = []
        key, val = m.group(1), m.group(2).strip()
        d[key] = val if val else ""
    if key is not None and buf: d[key] = "\n".join(buf)
    return d

def api(url, token, method="POST", data=None):
    args = ["curl", "-sS", "-X", method, "-H", "Authorization: Bearer " + token,
            "-H", "Accept: application/json", "-H", "Content-Type: application/json"]
    if data is not None: args += ["-d", json.dumps(data, ensure_ascii=False)]
    args.append(url)
    r = run(args)
    if r.returncode: raise RuntimeError("curl rc=%d: %s" % (r.returncode, r.stderr.strip()[-200:]))
    return json.loads(r.stdout or "{}")

def github_pr(conf, repo):
    tok = os.environ.get("GITHUB_TOKEN")
    if not tok: raise RuntimeError("GITHUB_TOKEN not set")
    body = {"title": conf["title"], "head": conf["branch"], "base": conf.get("base", "master"),
            "body": conf.get("body", "")}
    pr = api("%s/repos/%s/pulls" % (GH_API, repo), tok, "POST", body)
    if "number" not in pr: raise RuntimeError("github PR failed: " + str(pr)[:200])
    return pr["number"], pr.get("html_url", "")

def gitcode_mr(conf, repo):
    tok = os.environ.get("GITCODE_TOKEN")
    if not tok: raise RuntimeError("GITCODE_TOKEN not set")
    body = {"title": conf["title"], "source_branch": conf["branch"],
            "target_branch": conf.get("base", "master"), "description": conf.get("body", "")}
    mr = api("%s/repos/%s/merge_requests" % (GC_API, repo), tok, "POST", body)
    if "id" not in mr: raise RuntimeError("gitcode MR failed: " + str(mr)[:200])
    return mr["id"], mr.get("html_url", "")

def wait_gate(sha, repo, tok, timeout=900):
    url = "%s/repos/%s/commits/%s/check-runs" % (GH_API, repo, sha)
    for _ in range(int(timeout / 15)):
        runs = api(url, tok, "GET").get("check_runs", [])
        if runs:
            if any(r.get("conclusion") not in (None, "success") for r in runs):
                bad = [r for r in runs if r.get("conclusion") not in (None, "success")][0]
                raise RuntimeError("gate check %s: %s" % (bad.get("name"), bad.get("conclusion")))
            if all(r.get("status") == "completed" for r in runs): return True
        time.sleep(15)
    raise RuntimeError("gate timeout after %ds" % timeout)

def merge(number, repo, tok, platform):
    if platform == "github":
        r = api("%s/repos/%s/pulls/%d/merge" % (GH_API, repo, number), tok, "PUT",
                {"merge_method": "squash"})
        return r.get("merged", False), str(r.get("message", ""))[:120]
    r = api("%s/repos/%s/merge_requests/%d/merge" % (GC_API, repo, number), tok, "PUT")
    return r.get("state") == "merged", str(r.get("state", ""))[:120]

def pipeline(conf, repo, platform):
    branch = conf["branch"]; base = conf.get("base", "master")
    sh(["git", "rev-parse", "--verify", branch], cwd=ROOT)
    if conf.get("gate", "true").lower() != "false":
        r = run(["python", "scripts/fist-gate.py"], cwd=ROOT)
        if r.returncode >= 1:
            raise RuntimeError("local gate rc=%d tail: %s" % (r.returncode, (r.stdout or r.stderr).strip()[-160:]))
    sh(["git", "push", "-u", conf.get("remote", "origin"), branch], cwd=ROOT)
    head_sha = sh(["git", "rev-parse", branch], cwd=ROOT)
    tok = os.environ.get("GITHUB_TOKEN" if platform == "github" else "GITCODE_TOKEN")
    if platform == "github":
        num, url = github_pr(conf, repo); print("PR opened: " + url)
        wait_gate(head_sha, repo, tok)
    else:
        num, url = gitcode_mr(conf, repo); print("MR opened: " + url)
    if conf.get("merge", "true").lower() != "false":
        ok, msg = merge(num, repo, tok, platform)
        print("merged=%s %s" % (ok, msg))
    return 0

def selftest():
    txt = "id: TASK-005\ntitle: \"gate auto inject\"\npriority: P1\nbody: >-\n  line1\n  line2\n"
    d = parse_yaml(txt)
    ok = d.get("id") == "TASK-005" and d.get("priority") == "P1" and "line1" in d.get("body", "")
    print("SELFTEST %s (yaml parse: %s)" % ("OK" if ok else "FAIL", d))
    return 0 if ok else 2

if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]: sys.exit(selftest())
    if len(sys.argv) != 3: raise SystemExit("usage: python scripts/fist-pr-automator.py <pr.yaml> <github|gitcode>")
    conf = parse_yaml(Path(sys.argv[1]).read_text(encoding="utf-8"))
    if "branch" not in conf or "title" not in conf: raise SystemExit("yaml needs branch + title")
    repo = conf.get("repo", "vicTop-Cw/FIST-Mbt")
    sys.exit(pipeline(conf, repo, sys.argv[2]))
