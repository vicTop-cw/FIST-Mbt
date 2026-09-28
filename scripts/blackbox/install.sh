#!/usr/bin/env bash
# scripts/blackbox/install.sh —— curl 一条命令安装入口（Linux/WSL）
#
# 用户跑：
#   curl -fsSL https://gitcode.com/VictorTop/Fist-Mbt/-/raw/main/scripts/blackbox/install.sh | bash
# 或：
#   curl -fsSL https://raw.githubusercontent.com/vicTop-cw/FIST-Mbt/main/scripts/blackbox/install.sh | bash
#
# 下载源（自动 fallback）：
#   1. GitCode Release Assets 直链
#   2. GitHub Release Assets 直链

set -euo pipefail

VERSION="0.3.0-beta"
FORCE=""
DRY_RUN=""
for arg in "$@"; do
  case "$arg" in
    --force)   FORCE="1" ;;
    --dry-run) DRY_RUN="1" ;;
    -*) : ;;  # 忽略其它
    *)   VERSION="$arg" ;;  # 第一个非 flag 作 version
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   FIST-Mbt Installer  v${VERSION}${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# --- 0. 预检 ---
need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd node; then
  echo -e "${RED}❌ 需要 Node.js >=24${NC}"
  echo "   Ubuntu: curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt install -y nodejs"
  echo "   或:     nvm install 24"
  exit 1
fi

NV=$(node -v)
NM=$(echo "$NV" | sed 's/^v//' | cut -d. -f1)
if [ "$NM" -lt 24 ]; then
  echo -e "${RED}❌ Node.js $NV 过低，需要 >=v24${NC} (sqlite returnArrays 依赖)"
  exit 1
fi
echo -e "${GREEN}✅ node $NV${NC}"

if need_cmd python3; then
  PY=python3
  echo -e "${GREEN}✅ python3${NC}"
elif need_cmd python; then
  PY=python
  echo -e "${GREEN}✅ python${NC}"
else
  PY=""
  echo -e "${YELLOW}⚠️  python3 未找到，ESM patch 将跳过${NC}"
fi

# curl 或 wget
DL=""
if need_cmd curl; then DL="curl";
elif need_cmd wget; then DL="wget";
else echo -e "${RED}❌ 需要 curl 或 wget${NC}"; exit 1; fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if need_cmd sudo; then SUDO="sudo";
  else echo -e "${RED}❌ 需要 sudo 权限（或 root）${NC}"; exit 1; fi
fi

# --- 1. 构造下载 URL ---
ZIP="fist-mbt-js-v${VERSION}.zip"
URLS=(
  "https://gitcode.com/VictorTop/Fist-Mbt/-/releases/download/v${VERSION}/${ZIP}"
  "https://github.com/vicTop-cw/FIST-Mbt/releases/download/v${VERSION}/${ZIP}"
)

DEST="${HOME}/.local/share/fist-mbt"
BIN_DIR="${HOME}/.local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ""
echo -e "${YELLOW}📥 下载 ${ZIP} ...${NC}"
mkdir -p "$TMP"

ZIP_PATH="${TMP}/${ZIP}"
DOWNLOADED=0
for URL in "${URLS[@]}"; do
  echo -e "${DIM}  尝试: ${URL}${NC}"
  if [ "$DL" = "curl" ]; then
    curl -fsSL --max-time 60 -o "$ZIP_PATH" "$URL" 2>/dev/null || true
  else
    wget -q --timeout=60 -O "$ZIP_PATH" "$URL" 2>/dev/null || true
  fi
  if [ -f "$ZIP_PATH" ] && [ "$(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH")" -gt 10240 ]; then
    KS=$(( $(stat -c%s "$ZIP_PATH" 2>/dev/null || stat -f%z "$ZIP_PATH") / 1024 ))
    echo -e "${GREEN}  ✅ 下载成功 (${KS} KB)${NC}"
    DOWNLOADED=1; break
  else
    rm -f "$ZIP_PATH"
  fi
done

if [ "$DOWNLOADED" -eq 0 ]; then
  echo -e "${RED}❌ 下载全部失败 — Release 是否已发布？${NC}"
  exit 1
fi

# --- 2. 解压 ---
echo ""
echo -e "${YELLOW}📦 解压 ...${NC}"
cd "$TMP"
unzip -o "$ZIP_PATH" -d extracted >/dev/null 2>&1 || { echo -e "${RED}❌ 解压失败（需要 unzip）${NC}"; exit 1; }

JS_MAIN=$(find "$TMP/extracted" -maxdepth 2 -name "fist-mbt.js" | head -1)
if [ -z "$JS_MAIN" ]; then
  echo -e "${RED}❌ zip 里没找到 fist-mbt.js${NC}"; exit 1
fi
PY_PATCH=$(find "$TMP/extracted" -maxdepth 2 -name "patch_esm_main.py" | head -1)
echo -e "${GREEN}  ✅ fist-mbt.js${NC}"

# --- 3. 安装到 $DEST ---
echo ""
echo -e "${YELLOW}📦 安装到 ${DEST} ...${NC}"
if [ -d "$DEST" ] && [ -z "$FORCE" ]; then
  echo -e "${YELLOW}  ⚠️  已存在，加 --force 覆盖${NC}"
fi
mkdir -p "$DEST"
cp "$JS_MAIN" "$DEST/fist-mbt.js"
if [ -n "$PY_PATCH" ]; then cp "$PY_PATCH" "$DEST/patch_esm_main.py"; fi
echo '{"type":"module"}' > "$DEST/package.json"

# --- 4. ESM createRequire shim ---
if [ -n "$PY" ] && [ -n "$PY_PATCH" ]; then
  echo -e "${YELLOW}🔧 注入 ESM createRequire shim ...${NC}"
  $PY "$DEST/patch_esm_main.py" "$DEST/fist-mbt.js" 2>&1 | tail -1 || true
fi

# --- 5. shim + PATH ---
echo ""
echo -e "${YELLOW}🔧 创建 shim + PATH ...${NC}"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/fist" <<SHIM
#!/usr/bin/env bash
# FIST-Mbt shim — v${VERSION}
exec node "${DEST}/fist-mbt.js" "\$@"
SHIM
chmod +x "$BIN_DIR/fist"

cat > "$BIN_DIR/fist-mbt" <<SHIM2
#!/usr/bin/env bash
# FIST-Mbt shim (alias) — v${VERSION}
exec node "${DEST}/fist-mbt.js" "\$@"
SHIM2
chmod +x "$BIN_DIR/fist-mbt"

# 持久化 PATH 到 shell rc（只追加一次）
RC_FILE=""
case "${SHELL:-}" in
  */zsh) RC_FILE="${HOME}/.zshrc" ;;
  */bash) RC_FILE="${HOME}/.bashrc" ;;
  *)     RC_FILE="${HOME}/.profile" ;;
esac

PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
if [ -f "$RC_FILE" ]; then
  if ! grep -qF '.local/bin' "$RC_FILE" 2>/dev/null; then
    echo "" >> "$RC_FILE"
    echo "# FIST-Mbt installer" >> "$RC_FILE"
    echo "$PATH_LINE" >> "$RC_FILE"
    echo -e "${GREEN}  ✅ 追加 .local/bin 到 ${RC_FILE}${NC}"
  else
    echo -e "${DIM}  .local/bin 已在 ${RC_FILE}${NC}"
  fi
else
  echo "$PATH_LINE" > "$RC_FILE"
  echo -e "${GREEN}  ✅ 创建 ${RC_FILE}${NC}"
fi
export PATH="${BIN_DIR}:$PATH"

# --- 6. 自检 ---
echo ""
echo -e "${YELLOW}🏥 自检...${NC}"
V=$(node "${DEST}/fist-mbt.js" version 2>&1 | head -1)
echo -e "  ${GREEN}✅ ${V}${NC}"

V2=$("$BIN_DIR/fist" version 2>&1 | head -1)
echo -e "  ${GREEN}✅ fist (PATH) → ${V2}${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ FIST-Mbt v${VERSION} 安装完成！${NC}"
echo -e "${GREEN}║   新开终端后运行:  fist help${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${DIM}💡 已把 ${BIN_DIR} 追加到 ${RC_FILE} — 新开终端生效${NC}"

