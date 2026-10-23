#!/usr/bin/env python3

"""scripts/fist-pr-automator.py - yaml -> PR -> gate -> (explicit) merge pipeline.

Reads a PR definition yaml: runs the local unified gate, pushes the branch, opens

PR/MR via curl (GITHUB_TOKEN / GITCODE_TOKEN from the environment), and merges

ONLY when the yaml says `merge: true` (default OFF; R113/TASK-021).

`--dry-run` prints the plan and returns without spawning a process or touching

the network. The irreversible merge stays an explicit caller decision.

rc: 0=ok 1=blocked 2=degraded/self-refuse. Pure ASCII, stdlib only."""

import contextlib, io, json, os, re, subprocess, sys, time

from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

GH_API = "https://api.github.com"

GC_API = "https://gitcode.com/api/v5"

PLATFORMS = ("github", "gitcode")

def usage():

    """One-line CLI contract (also asserted by --selftest)."""

    return ("usage: python scripts/fist-pr-automator.py <pr.yaml> <github|gitcode> [--dry-run]"

            " | python scripts/fist-pr-automator.py --selftest")

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

def merge_requested(conf):

    """Only an explicit `merge: true` (case-insensitive, trimmed) enables the merge.

    Everything else - missing key, empty value, `false`, `yes` - stays OFF, so a

    yaml that never thought about merging cannot merge by accident."""

    return str(conf.get("merge", "")).strip().lower() == "true"

def gate_enabled(conf):

    """Local gate defaults ON; only a literal `gate: false` skips it."""

    return str(conf.get("gate", "true")).strip().lower() != "false"

def plan_lines(conf, repo, platform, token_present):

    """Deterministic dry-run plan. Pure: no env read, no subprocess, no network."""

    branch = conf["branch"]; base = conf.get("base", "master"); remote = conf.get("remote", "origin")

    if platform == "github":

        token_key = "GITHUB_TOKEN"

        open_line = "open PR: POST %s/repos/%s/pulls (token %s: %s)" % (

            GH_API, repo, token_key, "set" if token_present else "missing")

    else:

        token_key = "GITCODE_TOKEN"

        open_line = "open MR: POST %s/repos/%s/merge_requests (token %s: %s)" % (

            GC_API, repo, token_key, "set" if token_present else "missing")

    merge_line = ("merge: ON (yaml merge: true) -- irreversible" if merge_requested(conf)

                  else "merge: OFF (default; set 'merge: true' in the yaml to enable)")

    return [

        "DRY-RUN plan (no subprocess, no network):",

        "  branch: %s" % branch,

        "  base: %s" % base,

        "  remote: %s" % remote,

        "  local gate: %s" % ("run scripts/fist-gate.py" if gate_enabled(conf) else "skipped (gate: false)"),

        "  push: git push -u %s %s" % (remote, branch),

        "  " + open_line,

        "  " + merge_line,

        "  execute: rerun without --dry-run",

    ]

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

def pipeline(conf, repo, platform, dry_run=False):

    branch = conf["branch"]; base = conf.get("base", "master")

    token = os.environ.get("GITHUB_TOKEN" if platform == "github" else "GITCODE_TOKEN")

    if dry_run:

        for line in plan_lines(conf, repo, platform, bool(token)):

            print(line)

        return 0

    sh(["git", "rev-parse", "--verify", branch], cwd=ROOT)

    if gate_enabled(conf):

        r = run(["python", "scripts/fist-gate.py"], cwd=ROOT)

        if r.returncode >= 1:

            raise RuntimeError("local gate rc=%d tail: %s" % (r.returncode, (r.stdout or r.stderr).strip()[-160:]))

    sh(["git", "push", "-u", conf.get("remote", "origin"), branch], cwd=ROOT)

    head_sha = sh(["git", "rev-parse", branch], cwd=ROOT)

    if platform == "github":

        num, url = github_pr(conf, repo); print("PR opened: " + url)

        wait_gate(head_sha, repo, token)

    else:

        num, url = gitcode_mr(conf, repo); print("MR opened: " + url)

    if merge_requested(conf):

        ok, msg = merge(num, repo, token, platform)

        print("merged=%s %s" % (ok, msg))

    else:

        print("merge=off (default; set merge: true in the yaml to enable)")

    return 0

def selftest():

    checks = []

    def chk(name, cond):

        checks.append((name, bool(cond)))

    d = parse_yaml("id: TASK-005\ntitle: \"gate auto inject\"\npriority: P1\nbody: >-\n  line1\n  line2\n")

    chk("yaml-parse", d.get("id") == "TASK-005" and d.get("priority") == "P1" and "line1" in d.get("body", ""))

    g = {"branch": "slave/x", "title": "t"}

    chk("merge-default-off", not merge_requested({}))

    chk("merge-empty-off", not merge_requested({"merge": ""}))

    chk("merge-false-off", not merge_requested({"merge": "false"}))

    chk("merge-true-on", merge_requested({"merge": "true"}))

    chk("merge-true-trimmed-on", merge_requested({"merge": " TRUE "}))

    txt_off = "\n".join(plan_lines(g, "o/r", "gitcode", False))

    txt_on = "\n".join(plan_lines(dict(g, merge="true"), "o/r", "gitcode", True))

    txt_gate_off = "\n".join(plan_lines(dict(g, gate="false"), "o/r", "github", True))

    chk("plan-merge-off", "merge: OFF" in txt_off)

    chk("plan-token-missing", "token GITCODE_TOKEN: missing" in txt_off)

    chk("plan-push-line", "git push -u origin slave/x" in txt_off)

    chk("plan-merge-on", "merge: ON" in txt_on and "token GITCODE_TOKEN: set" in txt_on)

    chk("plan-gate-off", "skipped (gate: false)" in txt_gate_off)

    calls = []

    def boom(*a, **k):

        calls.append(a)

        raise AssertionError("dry-run touched an external face: %r" % (a[:1],))

    saved = (globals()["sh"], globals()["run"], globals()["api"])

    globals()["sh"] = boom; globals()["run"] = boom; globals()["api"] = boom

    buf = io.StringIO(); rc = 99; err = ""

    try:

        with contextlib.redirect_stdout(buf):

            rc = pipeline(g, "o/r", "gitcode", dry_run=True)

    except Exception as e:

        err = repr(e)

    finally:

        globals()["sh"], globals()["run"], globals()["api"] = saved

    chk("dry-run-rc0", rc == 0 and not err)

    chk("dry-run-zero-side-effects", calls == [])

    chk("dry-run-prints-plan", "DRY-RUN plan" in buf.getvalue())

    ebuf = io.StringIO()

    with contextlib.redirect_stderr(ebuf):

        chk("usage-no-args-rc2", main([]) == 2)

        chk("usage-dry-run-only-rc2", main(["--dry-run"]) == 2)

        chk("usage-bad-platform-rc2", main(["x.yaml", "gitlab"]) == 2)

    chk("usage-text", "usage:" in ebuf.getvalue())

    bad = [n for n, ok in checks if not ok]

    if bad:

        print("SELFTEST FAIL: " + ", ".join(bad))

        return 2

    print("SELFTEST OK (%d checks: %s)" % (len(checks), ", ".join(n for n, _ in checks)))

    return 0

def main(argv):

    if "--selftest" in argv:

        return selftest()

    dry_run = "--dry-run" in argv

    rest = [a for a in argv if a != "--dry-run"]

    if len(rest) != 2 or rest[1] not in PLATFORMS:

        sys.stderr.write(usage() + "\n")

        return 2

    conf = parse_yaml(Path(rest[0]).read_text(encoding="utf-8"))

    if "branch" not in conf or "title" not in conf:

        sys.stderr.write("yaml needs branch + title\n")

        return 2

    repo = conf.get("repo", "vicTop-Cw/FIST-Mbt")

    return pipeline(conf, repo, rest[1], dry_run=dry_run)

if __name__ == "__main__":

    sys.exit(main(sys.argv[1:]))
