#!/usr/bin/env bash
# scripts/blackbox/install.sh —— FIST-Mbt 黑盒安装（Linux / macOS）
#
# 来源: GitHub Releases (tag v<Version>)
# 安装: ~/.local/bin/fist-mbt
# 支持: js (node 运行) / native (若 CI 提供对应平台 binary)
#
# 用法:
#   ./scripts/blackbox/install.sh                         # 默认 JS 版
#   ./scripts/blackbox/install.sh --native                # 尝试 native
#   ./scripts/blackbox/install.sh --version 0.3.0         # 指定版本
#   ./scripts/blackbox/install.sh --source ./_release     # 从本地装
#
set -euo pipefail

VERSION="0.2.6"
REPO="AI/???"           # TODO: 替换为真实 GitHub repo path
SOURCE=""
NATIVE=0
JS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --native)  NATIVE=1; JS=0; shift ;;
        --js)      JS=1; NATIVE=0; shift ;;
        --all)     JS=1; NATIVE=1; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        --repo)    REPO="$2"; shift 2 ;;
        --source)  SOURCE="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/FIST-Mbt"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

echo "=== FIST-Mbt Install v$Version ($OS/$ARCH) ==="

fetch() {
    local fname="$1" url="$2" dest="$3"
    if [[ -n "$SOURCE" && -f "$SOURCE/$fname" ]]; then
        cp "$SOURCE/$fname" "$dest"
        echo "  ✅ 本地: $dest"
    elif [[ -n "$SOURCE" && -f "$SOURCE/js/$fname" ]]; then
        cp "$SOURCE/js/$fname" "$dest"
        echo "  ✅ 本地 (js/): $dest"
    else
        echo "  ↓ $url"
        curl -fsSL "$url" -o "$dest" || { echo "  ⚠️ 下载失败 (跳过)" >&2; return 1; }
        echo "  ✅ 远程: $dest"
    fi
}

installed=""

# JS 版
if [[ $JS -eq 1 ]]; then
    JS_URL="https://github.com/$REPO/releases/download/v$Version/fist-mbt-js-v$Version.zip"
    fetch "fist-mbt.js" "$JS_URL" "$INSTALL_DIR/fist-mbt.js.zip" || true
    if [[ -f "$INSTALL_DIR/fist-mbt.js.zip" ]]; then
        unzip -o "$INSTALL_DIR/fist-mbt.js.zip" -d "$INSTALL_DIR/_unpack" >/dev/null
        mv "$INSTALL_DIR/_unpack/fist-mbt.js" "$INSTALL_DIR/fist-mbt.js"
        rm -rf "$INSTALL_DIR/_unpack" "$INSTALL_DIR/fist-mbt.js.zip"
        installed="${installed}js "
    fi
fi

# Native 版
if [[ $NATIVE -eq 1 ]]; then
    NATIVE_BIN="fist-mbt"
    if [[ "$OS" == "linux" ]]; then
        NATIVE_ZIP="fist-mbt-native-linux-$ARCH-v$Version.zip"
    else
        NATIVE_ZIP="fist-mbt-native-macos-$ARCH-v$Version.zip"
    fi
    fetch "$NATIVE_ZIP" "https://github.com/$REPO/releases/download/v$Version/$NATIVE_ZIP" "$INSTALL_DIR/native.zip" || true
    if [[ -f "$INSTALL_DIR/native.zip" ]]; then
        unzip -o "$INSTALL_DIR/native.zip" -d "$INSTALL_DIR/_unpack" >/dev/null
        mv "$INSTALL_DIR/_unpack/fist-mbt" "$INSTALL_DIR/fist-mbt"
        chmod +x "$INSTALL_DIR/fist-mbt"
        rm -rf "$INSTALL_DIR/_unpack" "$INSTALL_DIR/native.zip"
        installed="${installed}native "
    fi
fi

if [[ -z "$installed" ]]; then
    echo "❌ 无可用二进制" >&2
    exit 1
fi

# Shim: 优先 native，fallback node + js
cat > "$BIN_DIR/fist-mbt" <<SHIM
#!/usr/bin/env bash
# FIST-Mbt shim — 由 install.sh 生成
HERE="$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/.."
NATIVE="$INSTALL_DIR/fist-mbt"
JS="$INSTALL_DIR/fist-mbt.js"
if [[ -x "\$NATIVE" ]]; then
    exec "\$NATIVE" "\$@"
fi
exec node "\$JS" "\$@"
SHIM
chmod +x "$BIN_DIR/fist-mbt"

echo ""
echo "=== 安装完成 ==="
echo "  已装: $installed"
echo "  数据: $INSTALL_DIR"
echo "  Shim: $BIN_DIR/fist-mbt"
echo "  若 fist-mbt 不在 PATH, 请确认 $BIN_DIR 在 PATH 中"
