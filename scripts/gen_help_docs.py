#!/usr/bin/env python3
"""gen_help_docs.py — Extract tool_groups from src/server/server.mbt.

READ-ONLY. Does NOT write any MoonBit files.
AI agent runs this when server.mbt tool_groups changes,
then manually updates cmd/cli/help_topics.mbt help_tools() via Write tool.

Usage:
  python scripts/gen_help_docs.py
"""
import re, os, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER_MBT = os.path.join(ROOT, '..', 'src', 'server', 'server.mbt')

def extract_tool_groups():
    with open(SERVER_MBT, 'r', encoding='utf-8') as f:
        src = f.read()
    m = re.search(r'"tool_groups"\s*:\s*Json::object\(\{(.*?)\}\)', src, re.DOTALL)
    if not m:
        print('ERROR: tool_groups block not found in server.mbt', file=sys.stderr)
        sys.exit(1)
    block = m.group(1)
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
