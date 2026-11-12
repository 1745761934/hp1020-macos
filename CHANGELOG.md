# Changelog

## v1.2.0 — 2026-11-12

### 修复：重复打印

三个成因，全部修掉。

- **USB 超时整块重发（根因）** —— `kIOReturnTimeout` 分支原本执行 `continue`，
  把整块 16 KB 重发。超时后数据往往已进打印机缓冲，重发即重复内容。
  现在超时直接中止，退出码 2，**绝不自动重发**。
- **未等待作业完成** —— 发送 97 KB 仅需 1 秒，渲染一页需数秒。旧版发完就退出，
  立刻再跑会叠加。现在等设备连续 3 次探测空闲才结束。
- **无作业互斥** —— 连按或重复调用会产生多个作业。现在用
  `/tmp/hp1020-print.lock` 挡住，持有进程已死时自动回收残留锁。

端点停摆（`kIOUSBPipeStalled`）仍可恢复，但只从当前位置续传、不回退，
且最多 3 次（`MAX_RETRIES`）。

### 新增

- `scripts/check_norepeat.py` —— 防重复打印不变量检查器
  - 超时分支不允许 `continue`
  - 发送循环内不允许回退 offset
  - 作业锁、等待逻辑、连续空闲判定必须存在
  - 发送后必须检查退出码
  - 已实测能抓到注入的回归
- CI 与 `make check` 均接入该检查

### 文档

- README 增加「关于重复打印」章节（中英双语）

## v1.1.0 — 2026-11-09

### 新增

- **`scripts/hp1020-fwinspect`** —— 固件格式检测器
  - 识别 6 种包装格式：`ACL/PJL`、`BARE_ELF`、`DATE+ELF`、`BEEF`、`HP_RAW_IMAGE`、`ARM2HPDL_WRAPPED`
  - 按 md5 匹配已知正确与已知错误版本
  - 解析封装内的 ELF 头（按 `EI_DATA` 判断字节序，正确识别 HP 私有机器码 `0xabc7`）
  - 支持 `--all DIR` 批量扫描、`--json` 机器可读输出
  - 退出码 0/1/2 便于 CI 与脚本集成
- **`hp1020-print --inspect`** —— 在主脚本内查看固件格式
- **固件推送前自检** —— `hp1020-print` 在推送前校验格式，格式不对直接拒绝
- **`hp1020-fwinspect` 全局命令** —— 安装时一并部署
- **`Makefile`** —— `build` / `universal` / `check` / `vendor` / `install` / `test` / `clean` / `help`
- **`scripts/selfcheck.sh`** —— 本地完整自检，与 CI 等价

### GitHub Actions（`.github/workflows/build.yml`）

全部跑在 `ubuntu-latest`（免费额度）：

- `verify-firmware` —— md5 + 大小 + 格式三重校验
- `test-inspector` —— 构造裸 ELF / 日期+ELF / beef / 不存在文件，验证判定与退出码
- `lint-scripts` —— bash/python 语法、可执行位、shellcheck、Makefile 目标、selfcheck
- `check-objc` —— 源码不变量（VID/PID、精确 FWVER、接口枚举、括号平衡）
- 支持 push / PR / 手动触发 / 每月定时

macOS 编译不在 CI 内：本仓库的 macOS runner 会在派发阶段被账号配额取消，任务拿不到 runner（`started_at == completed_at`，日志 blob 404）。已通过 probe workflow 确认 `ubuntu-latest` 正常、`macos-14` 必取消。编译改由本地 `make universal` 完成。

### 修复

- CI 中 `hp1020-fwinspect --json` 对错误格式返回 1，在 `pipefail` 下会中断断言
- `install.sh` 复用本机 Ghostscript 时找不到 `/usr/local/bin/gs-static`
- `install.sh` 在源与目标相同时触发 `install: same file` 错误
- `install.sh` 未部署固件检测器

---

## v1.0.0 — 2026-11-09

首个可用版本，在 macOS 26 / Apple Silicon 上验证通过。

### 核心

- 确认并验证正确的固件 `sihp1020.dl`：128999 字节，md5 `0cd1ac3a4f6cb7995e99deffff840927`，加载后 `FWVER:20080222`
- 记录三种会导致"接受成功但不执行"的错误固件格式，详见 README
- `bin/hp1020_usb`：基于 IOKit 的固件上传与原始数据发送工具
- `scripts/hp1020-print`：一键唤醒 + 编码 + 打印

### 特性

- 自动检测固件是否已加载，未加载则先推送
- 以 `FWVER:20080222` 为唯一判据，避免旧版固件误判
- 自动识别并跳过空白页
- 支持页范围打印

### 已知限制

- 每次打印机断电或拔插 USB 后需重新推送固件（约 10 秒，脚本已自动处理）
- 不复用 CUPS 队列，直接走 USB 发送
