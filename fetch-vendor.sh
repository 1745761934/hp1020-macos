#!/bin/bash
# 获取 vendor/ 下的第三方二进制（Ghostscript + foo2zjs）
#
# 优先使用本机已安装的版本，其次从 GitHub Release 下载。

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$DIR/vendor"
mkdir -p "$VENDOR"

REPO_SLUG="${HP1020_REPO:-1745761934/hp1020-macos}"
ASSET="https://github.com/$REPO_SLUG/releases/download/v1.0.0/vendor-binaries.tar.gz"

GS_MD5="d385c594463badc19f3ae4f798a5f987"
FZ_MD5="059b96fc46e238a7add2f3b40d5c29a0"

ok_gs() { [ -x "$VENDOR/gs-static" ]; }
ok_fz() { [ -x "$VENDOR/foo2zjs" ]; }

echo "==> 获取 vendor 二进制"

# ---------- 1. 优先复用本机已有版本 ----------
if ! ok_gs; then
    for c in /usr/local/bin/gs-static /opt/homebrew/bin/gs /usr/local/bin/gs /usr/bin/gs; do
        if [ -x "$c" ]; then
            echo "   发现本机 $c"
            cp "$c" "$VENDOR/gs-static"; chmod +x "$VENDOR/gs-static"; break
        fi
    done
fi

if ! ok_fz; then
    for c in /usr/libexec/cups/filter/foo2zjs /usr/local/bin/foo2zjs /opt/homebrew/bin/foo2zjs; do
        if [ -x "$c" ]; then
            echo "   发现本机 $c"
            cp "$c" "$VENDOR/foo2zjs"; chmod +x "$VENDOR/foo2zjs"; break
        fi
    done
fi

# ---------- 2. 仍缺失则从 Release 下载 ----------
if ! ok_gs || ! ok_fz; then
    echo "   从 release 下载 vendor-binaries.tar.gz（约 15 MB）"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    if curl -fsSL --max-time 600 -o "$TMP/v.tar.gz" "$ASSET"; then
        tar xzf "$TMP/v.tar.gz" -C "$TMP"
        if ! ok_gs && [ -f "$TMP/gs-static" ]; then
            cp "$TMP/gs-static" "$VENDOR/"; chmod +x "$VENDOR/gs-static"
        fi
        if ! ok_fz && [ -f "$TMP/foo2zjs" ]; then
            cp "$TMP/foo2zjs" "$VENDOR/"; chmod +x "$VENDOR/foo2zjs"
        fi
    else
        echo "   下载失败"
    fi
fi

# ---------- 3. 校验 ----------
echo
fail=0
if ok_gs; then
    a=$(md5 -q "$VENDOR/gs-static")
    if [ "$a" = "$GS_MD5" ]; then echo "  ok   gs-static  $a"
    else echo "  注意 gs-static md5 $a（与官方构建不同，可用但请留意）"; fi
else
    echo "  缺失 gs-static"; fail=1
fi

if ok_fz; then
    a=$(md5 -q "$VENDOR/foo2zjs")
    if [ "$a" = "$FZ_MD5" ]; then echo "  ok   foo2zjs    $a"
    else echo "  注意 foo2zjs md5 $a（与官方构建不同，可用但请留意）"; fi
else
    echo "  缺失 foo2zjs"; fail=1
fi

echo
if [ $fail -eq 0 ]; then
    echo "完成。下一步： ./install.sh"
else
    echo "有文件缺失，请参考 vendor/README.md 自行编译。"
    exit 1
fi
