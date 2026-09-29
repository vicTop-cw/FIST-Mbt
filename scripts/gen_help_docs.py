#!/usr/bin/env python3
"""gen_help_docs.py — Extract tool_groups from src/server/server.mbt.

READ-ONLY. Does NOT write any MoonBit files.

**边界（BUG-123，2026-09-29 实测）**：本脚本反解的是 MCP 资源面 `fist://map` 的 `tool_groups` 字段，
它按自身声明是一张**定位图**（12 组、组值用省略公共前缀的简写，如 `succeed status`、`append/get/export_tasks`），
**不是** 129 个工具的注册表，也不能与 `tools/list` 做机械差集（简写会让差集虚高：实测"未点名"虚报到 73）。

因此 `cmd/cli/help_topics.mbt::help_tools()` 的文案**不能**照本脚本落笔——那会把 CLI 帮助从
13 组/129 个倒退成 12 组/107 个。CLI 侧的权威面是 `node cli.js help tools` 的回执与
AGENTS.md/README.md 的工具表（由 `check_tools_sync` 的 J1/J2 钉住「逐个可查 + 分组和==实测」）。
本脚本的输出仅用于核对资源面自身的分组形状。

Usage:
  python scripts/gen_help_docs.py
"""
import re, os, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER_MBT = os.path.join(ROOT, '..', 'src', 'server', 'server.mbt')

def extract_tool_groups():
    with open(SERVER_MBT, 'r', encoding='utf-8') as f:
        src = f.read()
    # BUG-123：原先用 lazy 正则 `"tool_groups": Json::object({(.*?)})`，第一个 `})` 就把块切断了
    # （组值里有嵌套的 Json::object(...) / 带括号的中文说明），于是晚追加的组整个看不见 ——
    # 实测反解 12 组 107 个，而调用面 `fist help tools` 是 13 组 129 个。改成按花括号配平扫描。
    anchor = src.find(chr(34) + "tool_groups" + chr(34))
    if anchor < 0:
        print('ERROR: tool_groups block not found in server.mbt', file=sys.stderr)
        sys.exit(1)
    open_idx = src.index('{', src.index('Json::object', anchor))
    depth = 0
    end_idx = -1
    for i in range(open_idx, len(src)):
        ch = src[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                end_idx = i
                break
    if end_idx < 0:
        print('ERROR: tool_groups 花括号不配平（判据无法自证，绝不报绿）', file=sys.stderr)
        sys.exit(1)
    block = src[open_idx + 1:end_idx]

    # Normalize multi-line Json::string(...) into single line
    bn = re.sub(
        r'Json::string\(\s*\n\s*"(.*?)"\s*,?\s*\n\s*\)',
        lambda mm: 'Json::string("' + mm.group(1) + '")',
        block, flags=re.DOTALL
    )
    entries = []
    for line in bn.split('\n'):
        line = line.strip().rstrip(',')
        if not line:
            continue
        m2 = re.match(r'"(.*?)"\s*:\s*Json::string\("(.*?)"\)', line)
        if m2:
            gn = m2.group(1)
            tr = m2.group(2).replace(' + ', ' ').replace('/', ' ')
            tr = re.sub(r'[（(][^)）]*[)）]', '', tr)
            tr = re.sub(r'\s+', ' ', tr).strip()
            if tr:
                entries.append((gn, tr, len(tr.split())))
    return entries

def main():
    entries = extract_tool_groups()
    total = sum(e[2] for e in entries)

    print(f'## tool_groups snapshot: {len(entries)} groups, {total} tools')
    print('   边界（BUG-123）：这是 fist://map 的定位图，组值是简写（如 `succeed status`），不是 tools/list 的注册表。')
    print('   help_tools() 文案的权威面 = `node cli.js help tools` 的回执 + AGENTS/README 工具表（J1/J2 钉住）。')
    print()
    for gn, tr, n in entries:
        print(f'  [{gn} {n}] {tr}')
    print()

    print('## MoonBit help_tools() body (use Write tool to paste):')
    print()
    print('  let v = FIST_VERSION')
    # Note: In MoonBit double-quote strings, \\n means literal backslash+n
    # (the newline escape). The Write tool handles this correctly —
    # just use \n at end of each line item.
    print(f'  "=== " + v + "  ({total} MCP tools, {len(entries)} groups) ===\\n" +')
    print('  "\\n" +')
    for gn, tr, n in entries:
        print(f'  "  [{gn} {n}] {tr}\\n" +')
    print('  "\\n" +')
    print('  "  Per-tool detail: fist help tool <name>"')
    print()
    print('# After running: use Write tool to replace help_tools() body')
    print('# in cmd/cli/help_topics.mbt with the lines above.')

if __name__ == '__main__':
    main()
