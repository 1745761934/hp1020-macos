#!/bin/bash
# HP LaserJet 1020 on macOS — 安装脚本
# 安装 Ghostscript 与 foo2zjs，并部署 hp1020-print 到 /usr/local/bin

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/usr/local/share/hp1020"
BIN="/usr/local/bin"
FILTER="/usr/libexec/cups/filter"

die() { echo "错误: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "本脚本仅适用于 macOS"

ARCH=$(uname -m)
echo "==> 系统: macOS $(sw_vers -productVersion) / $ARCH"

# ---------- 1. Ghostscript ----------
GS="$DIR/vendor/gs-static"
if [ ! -x "$GS" ]; then
    echo "==> 未找到 vendor/gs-static"
    echo "    需要先获取静态编译的 Ghostscript（见 vendor/README.md）"
    found=""
    for c in "$BIN/gs-static" /usr/local/bin/gs /opt/homebrew/bin/gs /usr/bin/gs; do
        if [ -x "$c" ]; then found="$c"; break; fi
    done
    if [ -n "$found" ]; then
        echo "    复用本机已有的 $found"
        GS="$found"
    else
        die "缺少 Ghostscript。请先运行 ./fetch-vendor.sh，或按 vendor/README.md 自行编译"
    fi
fi
echo "==> Ghostscript: $("$GS" --version 2>/dev/null || echo '版本未知')"

# ---------- 2. foo2zjs ----------
FZ="$DIR/vendor/foo2zjs"
if [ ! -x "$FZ" ]; then
    if [ -x "$FILTER/foo2zjs" ]; then
        echo "==> 检测到已安装的 $FILTER/foo2zjs"
        FZ="$FILTER/foo2zjs"
    else
        die "缺少 foo2zjs。请按 vendor/README.md 放置 vendor/foo2zjs"
    fi
fi

# ---------- 3. 部署 ----------
echo "==> 安装到 $PREFIX"
sudo install -d -m 755 "$PREFIX/bin" "$PREFIX/fw" "$PREFIX/scripts"

sudo install -m 755 "$DIR/bin/hp1020_usb" "$PREFIX/bin/hp1020_usb"
sudo install -m 644 "$DIR/fw/sihp1020.dl"  "$PREFIX/fw/sihp1020.dl"
sudo install -m 755 "$DIR/scripts/hp1020-print" "$PREFIX/scripts/hp1020-print"
sudo install -m 755 "$DIR/scripts/hp1020-fwinspect" "$PREFIX/scripts/hp1020-fwinspect"

# 固件检测器的便捷入口
sudo tee "$BIN/hp1020-fwinspect" >/dev/null <<EOF
#!/bin/sh
exec "$PREFIX/scripts/hp1020-fwinspect" "\$@"
EOF
sudo chmod 755 "$BIN/hp1020-fwinspect"

# Ghostscript 与 foo2zjs 装到系统路径（供脚本默认查找）
# 源与目标相同时跳过，避免 install 报 "same file"
if [ "$(cd "$(dirname "$GS")" && pwd)/$(basename "$GS")" != "$BIN/gs-static" ]; then
    sudo install -m 755 "$GS" "$BIN/gs-static"
fi
if [ "$FZ" != "$FILTER/foo2zjs" ]; then
    sudo install -d -m 755 "$FILTER"
    sudo install -m 755 "$FZ" "$FILTER/foo2zjs"
fi

# 包装器
sudo tee "$BIN/hp1020-print" >/dev/null <<EOF
#!/bin/bash
export HP1020_HOME="$PREFIX"
exec "$PREFIX/scripts/hp1020-print" "\$@"
EOF
sudo chmod 755 "$BIN/hp1020-print"

# ---------- 4. 校验 ----------
echo
echo "==> 校验固件"
ACTUAL=$(md5 -q "$PREFIX/fw/sihp1020.dl")
EXPECT="0cd1ac3a4f6cb7995e99deffff840927"
[ "$ACTUAL" = "$EXPECT" ] || die "固件 md5 不符: $ACTUAL"
echo "    $ACTUAL  ok"

echo
echo "安装完成。"
echo
echo "用法:"
echo "  hp1020-print 文件.pdf        打印（自动跳过空白页）"
echo "  hp1020-print --status        查看状态"
echo "  hp1020-print --inspect       检查固件格式"
echo "  hp1020-fwinspect 文件        单独检查任意固件文件"
echo
echo "首次使用前请确认打印机已接电开机并连上 USB。"
