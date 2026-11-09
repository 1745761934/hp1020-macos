#!/bin/bash
# 下载 vendor/ 下的第三方二进制
# 若已有可用的系统版本，会直接复制，避免重复下载

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$DIR/vendor"
mkdir -p "$VENDOR"

GS_MD5="d385c594463badc19f3ae4f798a5f987"
FZ_MD5="059b96fc46e238a7add2f3b40d5c29a0"

# release 资源地址（首次发布后填写；也可自行编译，见 vendor/README.md）
REPO_SLUG="${HP1020_REPO:-1745761934/hp1020-macos}"
REL="https://github.com/$REPO_SLUG/releases/latest/download"

fetch_one() {
    local name="$1" md5="$2" url="$3"
    local dest="$VENDOR/$name"

    if [ -f "$dest" ] && [ "$(md5 -q "$dest")" = "$md5" ]; then
        echo "  ok   $name 已存在"
        return 0
    fi

    echo "  ...  $name 下载中（release）"
    if curl -fsSL --max-time 300 -o "$dest.tmp" "$url" 2>/dev/null; then
        if [ "$(md5 -q "$dest.tmp")" = "$md5" ]; then
            mv "$dest.tmp" "$dest"; chmod +x "$dest"
            echo "  ok   $name"
            return 0
        fi
        echo "  !!   $name 校验失败"
        rm -f "$dest.tmp"
    fi
    return 1
}

echo "==> 获取 vendor 二进制"

# 优先用本机已有版本
if [ ! -x "$VENDOR/gs-static" ]; then
    for c in /usr/local/bin/gs-static /opt/homebrew/bin/gs /usr/local/bin/gs; do
        if [ -x "$c" ]; then
            echo "  发现本机 $c，复制为 vendor/gs-static"
            cp "$c" "$VENDOR/gs-static"; chmod +x "$VENDOR/gs-static"; break
        fi
    done
fi

if [ ! -x "$VENDOR/foo2zjs" ]; then
    for c in /usr/libexec/cups/filter/foo2zjs /usr/local/bin/foo2zjs; do
        if [ -x "$c" ]; then
            echo "  发现本机 $c，复制为 vendor/foo2zjs"
            cp "$c" "$VENDOR/foo2zjs"; chmod +x "$VENDOR/foo2zjs"; break
        fi
    done
fi

# 仍缺失则尝试 release
if [ ! -x "$VENDOR/gs-static" ]; then
    fetch_one "gs-static" "$GS_MD5" "$REL/gs-static" || \
        echo "  !! 无法获取 gs-static，请参考 vendor/README.md 自行编译"
fi
if [ ! -x "$VENDOR/foo2zjs" ]; then
    fetch_one "foo2zjs" "$FZ_MD5" "$REL/foo2zjs" || \
        echo "  !! 无法获取 foo2zjs，请参考 vendor/README.md 自行编译"
fi

echo
ls -lh "$VENDOR" 2>/dev/null | grep -v '^total'
echo
echo "完成。下一步： ./install.sh"
