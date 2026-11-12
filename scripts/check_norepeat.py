#!/usr/bin/env python3
"""
检查源码与脚本里的防重复打印不变量。

重复打印的根因是 USB 超时后整块重发，所以这里把"超时不许重发"
固化成可自动验证的规则，防止以后被改回去。

用法: python3 scripts/check_norepeat.py [仓库根目录]
"""

import os
import re
import sys


def find_block(src, keyword):
    """取出 keyword) { ... } 的花括号块内容，按括号配对。"""
    idx = src.find(keyword)
    if idx < 0:
        return None
    brace = src.find("{", idx)
    if brace < 0:
        return None
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace + 1:i]
    return None


def strip_comments(code):
    """去掉 // 与 /* */ 注释，避免注释里的词造成误判。"""
    code = re.sub(r"//[^\n]*", "", code)
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    return code


def check_timeout_no_resend(root):
    path = os.path.join(root, "src", "hp1020_usb.m")
    if not os.path.isfile(path):
        return False, "缺少 src/hp1020_usb.m"

    src = open(path, encoding="utf-8").read()
    body = find_block(src, "kIOReturnTimeout")
    if body is None:
        return False, "找不到 kIOReturnTimeout 分支"

    code = strip_comments(body)

    if re.search(r"\bcontinue\s*;", code):
        return False, (
            "kIOReturnTimeout 分支里有 continue —— 会整块重发，"
            "导致打印机重复输出同一段内容。超时必须直接中止。"
        )

    if not re.search(r"\breturn\b", code):
        return False, "超时分支必须 return，不能继续发送"

    return True, "超时分支不重发，且有 return"


def check_no_retry_of_sent_data(root):
    """确认没有把已发出数据的 offset 回退（那是重复的另一条路径）。"""
    path = os.path.join(root, "src", "hp1020_usb.m")
    if not os.path.isfile(path):
        return False, "缺少 src/hp1020_usb.m"

    src = open(path, encoding="utf-8").read()
    code = strip_comments(src)

    # off = 0 只允许出现在初始化处；循环内回退 offset 就意味着重发
    loop_start = code.find("while (off < n)")
    if loop_start < 0:
        return False, "找不到发送循环"

    loop_body = code[loop_start:]
    if re.search(r"\boff\s*=\s*0\s*;", loop_body):
        return False, "发送循环内把 off 归零 —— 会重复发送已送出的数据"

    return True, "发送循环内未回退 offset"


def check_job_lock(root):
    path = os.path.join(root, "scripts", "hp1020-print")
    if not os.path.isfile(path):
        return False, "缺少 scripts/hp1020-print"

    src = open(path, encoding="utf-8").read()

    if "hp1020-print.lock" not in src:
        return False, "缺少作业锁（并发/重复触发会产生多个作业）"
    if "wait_for_idle" not in src:
        return False, "缺少等待作业完成的逻辑"
    if "IDLE_CONFIRM" not in src:
        return False, "空闲判定应为连续多次探测，单次会误判"

    return True, "作业锁、等待逻辑、连续空闲判定均在"


def check_send_exit_checked(root):
    """发送后必须检查退出码，否则失败会被当成成功。"""
    path = os.path.join(root, "scripts", "hp1020-print")
    if not os.path.isfile(path):
        return False, "缺少 scripts/hp1020-print"

    src = open(path, encoding="utf-8").read()
    if "PIPESTATUS" not in src and "send_rc" not in src:
        return False, "发送后未检查退出码"
    return True, "发送后检查了退出码"


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    root = os.path.abspath(root)

    checks = [
        ("超时不重发", check_timeout_no_resend),
        ("不回退发送偏移", check_no_retry_of_sent_data),
        ("作业互斥锁", check_job_lock),
        ("发送退出码校验", check_send_exit_checked),
    ]

    failed = 0
    for name, fn in checks:
        ok, msg = fn(root)
        if ok:
            print("  ok   %s — %s" % (name, msg))
        else:
            print("  FAIL %s — %s" % (name, msg))
            failed = 1

    print()
    if failed:
        print("防重复打印不变量检查未通过")
        return 1
    print("防重复打印不变量全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
