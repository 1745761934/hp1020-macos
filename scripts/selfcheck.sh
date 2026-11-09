#!/bin/bash
# 本地自检 —— 与 GitHub Actions 的检查等价
# 用法: bash scripts/selfcheck.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

fail=0
pass() { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }

md5_of() {
    if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
    else md5sum "$1" | cut -d' ' -f1; fi
}
size_of() {
    if stat -f%z "$1" >/dev/null 2>&1; then stat -f%z "$1"
    else stat -c%s "$1"; fi
}

echo "=== 1. 固件完整性 ==="
EXPECT_MD5=0cd1ac3a4f6cb7995e99deffff840927
if [ -f fw/sihp1020.dl ]; then
    m=$(md5_of fw/sihp1020.dl)
    s=$(size_of fw/sihp1020.dl)
    [ "$m" = "$EXPECT_MD5" ] && pass "md5 $m" || bad "md5 $m（应为 $EXPECT_MD5）"
    [ "$s" = "128999" ] && pass "大小 $s" || bad "大小 $s（应为 128999）"
else
    bad "缺少 fw/sihp1020.dl"
fi

echo
echo "=== 2. 固件格式 ==="
if [ -x scripts/hp1020-fwinspect ]; then
    if ./scripts/hp1020-fwinspect fw/sihp1020.dl >/dev/null 2>&1; then
        pass "判定 GOOD"
    else
        bad "判定不是 GOOD"
        ./scripts/hp1020-fwinspect fw/sihp1020.dl 2>&1 | sed 's/^/       /'
    fi
else
    bad "scripts/hp1020-fwinspect 不可执行"
fi

echo
echo "=== 3. 脚本语法 ==="
for f in install.sh fetch-vendor.sh scripts/hp1020-print; do
    if bash -n "$f" 2>/dev/null; then pass "$f"; else bad "$f 语法错误"; fi
done
if python3 -m py_compile scripts/hp1020-fwinspect 2>/dev/null; then
    pass "scripts/hp1020-fwinspect"
else
    bad "scripts/hp1020-fwinspect 语法错误"
fi

echo
echo "=== 4. 可执行位 ==="
for f in install.sh fetch-vendor.sh scripts/hp1020-print scripts/hp1020-fwinspect bin/hp1020_usb; do
    if [ -x "$f" ]; then pass "$f"; else bad "$f 缺少可执行权限"; fi
done

echo
echo "=== 5. 检测器回归 ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
INS="$DIR/scripts/hp1020-fwinspect"

cp fw/sihp1020.dl "$TMP/correct.dl"
if "$INS" "$TMP/correct.dl" >/dev/null 2>&1; then
    pass "正确固件 -> GOOD"
else
    bad "正确固件判定错误"
fi

python3 - fw/sihp1020.dl "$TMP" <<'PY'
import sys
blob = open(sys.argv[1], 'rb').read()
pos = blob.find(b'\x7fELF')
out = sys.argv[2]
open(out + '/bare.bin', 'wb').write(blob[pos:])
open(out + '/date.bin', 'wb').write(b'20050309' + blob[pos:])
PY

if "$INS" "$TMP/bare.bin" >/dev/null 2>&1; then
    bad "裸 ELF 不应判为 GOOD"
else
    pass "裸 ELF -> BAD_FORMAT"
fi

if "$INS" "$TMP/date.bin" >/dev/null 2>&1; then
    bad "日期+ELF 不应判为 GOOD"
else
    pass "日期+ELF -> BAD_FORMAT"
fi

printf '\xbe\xef0000rest' > "$TMP/beef.bin"
fmt=$("$INS" --json "$TMP/beef.bin" 2>/dev/null || true)
case "$fmt" in
    *'"format": "BEEF"'*) pass "beef -> BAD_FORMAT" ;;
    *) bad "beef 识别错误" ;;
esac

set +e
"$INS" "$TMP/nosuch.dl" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "2" ] && pass "不存在文件 -> exit 2" || bad "不存在文件应返回 2，实际 $rc"

echo
if [ $fail -eq 0 ]; then
    echo "全部检查通过"
    exit 0
else
    echo "存在失败项"
    exit 1
fi
