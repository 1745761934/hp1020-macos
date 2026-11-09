# Changelog

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

### GitHub Actions（`.github/workflows/build.yml`）

- `build-binary` —— arm64 / x86_64 矩阵编译，开启 `-Wall -Wextra`
- `make-universal` —— lipo 合并，并与仓库内二进制比对
- `verify-firmware` —— md5 + 大小 + 格式三重校验
- `lint-scripts` —— bash/python 语法、可执行位、shellcheck
- `test-inspector` —— 构造裸 ELF / 日期+ELF / beef / 不存在文件，验证判定与退出码
- 支持 push / PR / 手动触发 / 每月定时

### 修复

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
