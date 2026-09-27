#!/usr/bin/env bash
# scripts/blackbox/install.sh —— FIST-Mbt 黑盒安装（Linux / macOS）
#
# 来源: GitHub Releases → GitCode Releases fallback
# 安装: ~/.local/bin/fist-mbt
# 支持: js (node 运行) / native (若 CI 提供对应平台 binary)
#
# 用法:
#   ./scripts/blackbox/install.sh                         # 默认 JS 版
#   ./scripts/blackbox/install.sh --native                # 尝试 native
#   ./scripts/blackbox/install.sh --version 0.3.0         # 指定版本
#   ./scripts/blackbox/install.sh --source ./_release     # 从本地装
#   ./scripts/blackbox/install.sh --install-service       # 安装 systemd --user unit
#
set -euo pipefail

# ---------- Repo ----------
GITHUB_REPO="vicTop-cw/FIST-Mbt"
GITCODE_REPO="VictorTop/Fist-Mbt"

# ---------- 参数 ----------
VERSION=""
SOURCE=""
NATIVE=0
JS=1
INSTALL_SERVICE=0
NO_PATH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --native)         NATIVE=1; JS=0; shift ;;
        --js)             JS=1; NATIVE=0; shift ;;
        --all)            JS=1; NATIVE=1; shift ;;
        --version)        VERSION="$2"; shift 2 ;;
        --repo)           GITHUB_REPO="$2"; shift 2 ;;
        --source)         SOURCE="$2"; shift 2 ;;
        --install-service) INSTALL_SERVICE=1; shift ;;
        --no-path)        NO_PATH=1; shift ;;
        -h|--help)        sed -n '2,26p' "$0"; exit ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

# ---------- 安装目录 ----------
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/FIST-Mbt"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# ---------- 推断版本 ----------
if [[ -z "$VERSION" ]]; then
    if [[ -n "$SOURCE" && -f "$SOURCE/VERSION" ]]; then
        VERSION="$(cat "$SOURCE/VERSION" | tr -d '\r\n')"
        echo "[VERSION] 从本地: $VERSION"
    else
        VERSION="0.3.0"
        echo "[VERSION] 默认: $VERSION (可 --version 指定)"
    fi
fi

# ---------- OS / ARCH ----------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

echo "=== FIST-Mbt Install v$VERSION ($OS/$ARCH) ==="

# ---------- Node >=24 检查 ----------
test_node() {
    local min_major=24
    if ! command -v node >/dev/null 2>&1; then
        echo "  [WARN] node 未找到 (需要 >=v$min_major)" >&2
        return 1
    fi
    local major
    major="$(node -v 2>/dev/null | grep -oP '\d+' | head -1)"
    if [[ "$major" -lt "$min_major" ]]; then
        echo "  [WARN] node 版本过低: $(node -v) (需要 >=v$min_major)" >&2
        return 1
    fi
    echo "  node $(node -v) OK"
    return 0
}

# ---------- 双源 fetch ----------
fetch_url() {
    local filename="$1" version="$2" dest="$3"
    local url1="https://github.com/$GITHUB_REPO/releases/download/v$version/$filename"
    local url2="https://gitcode.com/$GITCODE_REPO/releases/download/v$version/$filename"

    echo "  GitHub: $url1"
    if curl -fsSL --max-time 30 "$url1" -o "$dest"; then
        echo "  ✅ GitHub 下载成功"
        return 0
    fi
    echo "  ⚠️ GitHub 失败，尝试 GitCode fallback"
    if curl -fsSL --max-time 30 "$url2" -o "$dest"; then
        echo "  ✅ GitCode fallback 成功"
        return 0
    fi
    echo "  ❌ 都失败"
    rm -f "$dest"
    return 1
}

# ---------- 本地或远程获取 ----------
acquire() {
    local filename="$1" version="$2" dest="$3"
    # 本地搜索
    if [[ -n "$SOURCE" ]]; then
        for sub in "" "js" "native"; do
            local cand
            if [[ -n "$sub" ]]; then
                cand="$SOURCE/$sub/$filename"
            else
                cand="$SOURCE/$filename"
            fi
            if [[ -f "$cand" ]]; then
                cp "$cand" "$dest"
                echo "  ✅ 本地: $cand"
                return 0
            fi
        done
        # 裸文件（不带 zip）
        local bare="$SOURCE/$filename"
        # 尝试直接从 _release 根拿
        bare="$SOURCE/$filename"
        if [[ -f "$bare" ]]; then
            cp "$bare" "$dest"
            echo "  ✅ 本地裸文件: $bare"
            return 0
        fi
    fi
    fetch_url "$filename" "$version" "$dest"
}

installed=""

# ---------- JS 版 ----------
if [[ $JS -eq 1 ]]; then
    test_node || true
    JS_ZIP="fist-mbt-js-v$VERSION.zip"
    acquire "$JS_ZIP" "$VERSION" "$INSTALL_DIR/js.zip" || true
    if [[ -f "$INSTALL_DIR/js.zip" ]]; then
        local_unpack="$(mktemp -d)"
        unzip -o "$INSTALL_DIR/js.zip" -d "$local_unpack" >/dev/null
        # 找主程序和 patch
        find "$local_unpack" -type f -name "fist-mbt.js" -exec mv {} "$INSTALL_DIR/fist-mbt.js" \;
        find "$local_unpack" -type f -name "patch_esm_main.py" -exec mv {} "$INSTALL_DIR/patch_esm_main.py" \;
        rm -rf "$local_unpack" "$INSTALL_DIR/js.zip"
        if [[ -f "$INSTALL_DIR/fist-mbt.js" ]]; then
            installed="${installed}js "
            echo "  ✅ JS: $INSTALL_DIR/fist-mbt.js"
        fi
    fi
fi

# ---------- Native 版 ----------
if [[ $NATIVE -eq 1 ]]; then
    NATIVE_ZIP=""
    if [[ "$OS" == "linux" ]]; then
        NATIVE_ZIP="fist-mbt-native-linux-$ARCH-v$VERSION.zip"
    elif [[ "$OS" == "darwin" ]]; then
        NATIVE_ZIP="fist-mbt-native-macos-$ARCH-v$VERSION.zip"
    else
        echo "  [SKIP] 未知 OS: $OS, 不装 native"
    fi
    if [[ -n "$NATIVE_ZIP" ]]; then
        acquire "$NATIVE_ZIP" "$VERSION" "$INSTALL_DIR/native.zip" || true
        if [[ -f "$INSTALL_DIR/native.zip" ]]; then
            local_unpack="$(mktemp -d)"
            unzip -o "$INSTALL_DIR/native.zip" -d "$local_unpack" >/dev/null
            # 找 fist-mbt binary
            local bin_path
            bin_path="$(find "$local_unpack" -type f \( -name "fist-mbt" -o -name "fist-mbt.exe" \) | head -1)"
            if [[ -n "$bin_path" ]]; then
                mv "$bin_path" "$INSTALL_DIR/fist-mbt"
                chmod +x "$INSTALL_DIR/fist-mbt"
                installed="${installed}native "
                echo "  ✅ Native: $INSTALL_DIR/fist-mbt"
            fi
            rm -rf "$local_unpack" "$INSTALL_DIR/native.zip"
        fi
    fi
fi

if [[ -z "$installed" ]]; then
    echo "❌ 无可用二进制（检查 --source / --version / 网络）" >&2
    exit 1
fi

# ---------- Shim ----------
cat > "$BIN_DIR/fist-mbt" <<SHIM
#!/usr/bin/env bash
# FIST-Mbt shim — v$VERSION
HERE="$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$INSTALL_DIR/fist-mbt"
JS="$INSTALL_DIR/fist-mbt.js"
PATCH="$INSTALL_DIR/patch_esm_main.py"
if [[ -x "\$NATIVE" ]]; then
    exec "\$NATIVE" "\$@"
fi
# 若 ESM require 报错, 运行 python "\$PATCH" "\$JS" 重新 patch
exec node "\$JS" "\$@"
SHIM
chmod +x "$BIN_DIR/fist-mbt"
echo "  ✅ Shim: $BIN_DIR/fist-mbt"

# ---------- PATH 提示 ----------
if [[ $NO_PATH -eq 0 ]]; then
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo "  ⚠️  $BIN_DIR 不在 PATH 中"
        echo "     请加到 shell 配置, 例如 bash:"
        echo "       echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc"
        echo "     或 zsh:"
        echo "       echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
    fi
fi

# ---------- systemd --user unit (可选) ----------
if [[ $INSTALL_SERVICE -eq 1 ]] && command -v systemctl >/dev/null 2>&1; then
    UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/fist-mbt.service" << UNIT
[Unit]
Description=FIST-Mbt CLI Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_DIR/fist-mbt --serve
Restart=on-failure
RestartSec=5
Environment=PATH=$BIN_DIR:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
UNIT
    systemctl --user daemon-reload 2>/dev/null || true
    echo "  ✅ systemd unit: $UNIT_DIR/fist-mbt.service"
    echo "     启用: systemctl --user enable --now fist-mbt"
    echo "     状态: systemctl --user status fist-mbt"
fi

# ---------- ESM patch（JS 版）----------
if [[ $NATIVE -eq 0 ]] && [[ -f "$INSTALL_DIR/fist-mbt.js" ]] && [[ -f "$INSTALL_DIR/patch_esm_main.py" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 "$INSTALL_DIR/patch_esm_main.py" "$INSTALL_DIR/fist-mbt.js" | while IFS= read -r line; do echo "  patch: $line"; done
    elif command -v python >/dev/null 2>&1; then
        python "$INSTALL_DIR/patch_esm_main.py" "$INSTALL_DIR/fist-mbt.js" | while IFS= read -r line; do echo "  patch: $line"; done
    else
        echo "  (ESM patch 跳过: python 不可用)"
    fi
fi

# ---------- Doctor 自检 ----------
if [[ $NATIVE -eq 0 ]] && [[ -f "$INSTALL_DIR/fist-mbt.js" ]]; then
    echo ""
    echo "=== 自检: fist-mbt doctor ==="
    node "$INSTALL_DIR/fist-mbt.js" doctor 2>&1 | tail -8
fi

echo ""
echo "=== 安装完成 ==="
echo "  已装: $installed"
echo "  数据: $INSTALL_DIR"
echo "  Shim: $BIN_DIR/fist-mbt"
echo "  运行: fist-mbt --help"
