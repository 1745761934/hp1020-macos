# HP LaserJet 1020 on macOS

让 **HP LaserJet 1020 / 1020 Plus** 在 macOS 上正常打印。

针对 Apple Silicon（M1/M2/M3/M4）与 Intel Mac 均可，macOS 12 及以上验证。

> [English](README_EN.md)

```
PDF ──► Ghostscript ──► pbmraw ──► foo2zjs ──► ZJS ──► USB ──► 打印机
```

---

## 为什么需要这个项目

HP LaserJet 1020 是一台**"哑打印机"**（host-based / GDI）：

- 没有常驻固件，没有页面描述语言，只有很小的 RAM 缓冲
- 页面渲染完全由主机 CPU 完成
- **每次断电或拔插 USB 后，主机必须先把运行时固件推进它的 RAM**，它才能工作

HP 官方的 macOS 驱动早已停止更新，Apple 的 HP Printer Drivers 包最后一次更新在 2015 年，且在新版 macOS 上被安装器的版本检查挡住。同时社区流传的固件文件**版本混乱**，绝大多数是错的那几个 —— 这就是"驱动装好了、作业显示完成、但打印机一动不动"的根本原因。

本项目的核心价值是：**把固件格式这件事讲清楚**，并提供一套经过验证的完整流程。

---

## 快速开始

```bash
git clone https://github.com/<你的用户名>/hp1020-macos.git
cd hp1020-macos

# 下载 vendor 二进制（Ghostscript + foo2zjs）
./fetch-vendor.sh

# 安装到系统
./install.sh

# 打印
hp1020-print 文档.pdf
```

首次使用前确认打印机已接电、已连 USB。

---

## 固件：整个问题的关键

这是最值得读的一节。**看到 `FWVER` 出现，不代表固件真的跑起来了。**

### 正确的固件

| 项目 | 值 |
|---|---|
| 文件 | `fw/sihp1020.dl` |
| 大小 | **128999** 字节 |
| md5 | **`0cd1ac3a4f6cb7995e99deffff840927`** |
| 格式 | ACL/PJL |
| 开头字节 | `1b 25 2d 31 32 33 34 35 58` = `\x1b%-12345X@PJL ENTER LANGUAGE=ACL` |
| 正确加载后版本 | **`FWVER:20080222`** |

验证：

```bash
md5 fw/sihp1020.dl
# 0cd1ac3a4f6cb7995e99deffff840927

head -c 24 fw/sihp1020.dl | xxd
# 00000000: 1b25 2d31 3233 3435 5840 504a 4c20 454e  .%-12345X@PJL EN
# 00000010: 5445 5220 4c41 4e47                      TER LANG
```

### 三种会导致"假装成功"的错误格式

| 错误做法 | 现象 |
|---|---|
| 推**裸 ELF**（`\x7fELF` 开头，例如 Apple 驱动包里的 `hp1020.acl`） | 打印机接受字节、返回成功、甚至回显版本号，但**固件永不执行**。不打印。 |
| 用 `arm2hpdl` 转换裸 ELF，得到 `\xbe\xef`（"beef"）头 | 同上 |
| 使用过旧版本的 `.dl`（如 md5 `dea9e815` / 128431 字节，或 `86403c3b` / 126151 字节） | 版本号能回显，但成像失败，出白纸 |

### 为什么 `arm2hpdl` 是个陷阱

`arm2hpdl` 有**两条截然不同的输出路径**，取决于输入的头部字节：

| 输入开头 | `arm2hpdl` 输出 | LJ 1020 可用 |
|---|---|---|
| `\x7fELF`（裸 ARM/Linux ELF） | `\xbe\xef` HP 下载头（"beef"） | **否** |
| ASCII `20...`（HP *原始*镜像，如 `sihp1020.img`） | ACL/PJL 封装 | **是** |
| `\xbe\xef`（已是 beef） | 原样透传 | **否** |

把裸 ELF 喂给它再上传，**打印机会接受字节并返回成功，但永不运行** —— 没有 FWVER，不出纸。这是这个型号最令人困惑的失败模式。

正确做法：

- 用 HPLIP 的 `hp_laserjet_1020.fw.gz`（已是 ACL/PJL，无需转换）
- 或用 `foo2zjs` 的 `getweb` 下载 HP 原始镜像，再 `arm2hpdl` 转换
- **不要手工把裸 ELF 包一层**

### 用工具检查固件格式

不用肉眼判断，仓库自带检测器：

```bash
./scripts/hp1020-fwinspect fw/sihp1020.dl
```

```
  文件:   fw/sihp1020.dl
  大小:   128999 字节
  md5:    0cd1ac3a4f6cb7995e99deffff840927
  格式:   ACL/PJL
  开头:   1b252d31323334355840504a4c20454e
  FWVER:  20080822
  ELF:    ELF32 BE ARM(HP custom) EXEC @ offset 50
  判定:   ✓ GOOD
```

扫描一个目录下所有候选固件：

```bash
./scripts/hp1020-fwinspect --all ~/Downloads
```

机器可读输出（脚本集成用）：

```bash
./scripts/hp1020-fwinspect --json fw/sihp1020.dl
```

退出码：`0` 正确 / `1` 错误格式 / `2` 文件不存在。

能识别的格式：

| 格式标记 | 含义 | 可用 |
|---|---|---|
| `ACL/PJL` | 带 `@PJL ENTER LANGUAGE=ACL` 封装 | 视版本而定 |
| `BARE_ELF` | 裸 ELF，无封装 | ✗ |
| `DATE+ELF` | 日期串直接接 ELF（Apple 的 `.acl`） | ✗ |
| `BEEF` | `arm2hpdl` 的 beef 头 | ✗ |
| `HP_RAW_IMAGE` | HP 原始镜像，需 `arm2hpdl` 转换 | → |
| `ARM2HPDL_WRAPPED` | `arm2hpdl` 中间封装 | ✗ |

`hp1020-print` 在推送固件前会自动跑这个检查。**格式不对就拒绝推送** —— 因为推错格式会把打印机的 USB 控制器打进异常态，需要拔电源才能恢复。

### 固件版本对照表

| FWVER | 判定 |
|---|---|
| `20080222` | ✅ 正确 |
| `20050309` | ❌ 旧版，出白纸 |
| `20041129` | ❌ 更旧 |
| 无 FWVER | ❌ 未加载 |

---

## 是否已经加载？

```bash
hp1020-print --status
```

输出：

```
  Device ID: MFG:Hewlett-Packard;MDL:HP LaserJet 1020;CMD:ACL;CLS:PRINTER;DES:HP LaserJet 1020;FWVER:20080222;
  firmware_loaded=yes
  就绪，可以打印
```

脚本以 `FWVER:20080222` 为唯一判据，不是看到 FWVER 就算数。

---

## 用法

```bash
hp1020-print 文档.pdf              # 自动跳过空白页
hp1020-print 文档.pdf 1            # 只打第 1 页
hp1020-print 文档.pdf 1-3          # 打 1 到 3 页
hp1020-print --status              # 打印机状态
hp1020-print --firmware            # 只推固件
hp1020-print --pages 文档.pdf      # 查看哪些页有内容
hp1020-print --check               # 检查依赖
hp1020-print --inspect             # 检查固件文件格式
```

`--pages` 用 Ghostscript 的 bbox 判断每页着墨范围，能正确识别空白页 —— 扫描件常见的"最后一页纯白"会被自动跳过。

---

## 技术细节

### 数据管线

```
PDF/PS
  │  gs-static -sDEVICE=pbmraw -r1200x600 -sPAPERSIZE=a4
  ▼
pbmraw 位图
  │  foo2zjs -r1200x600 -p9 -P -z1 -L0
  ▼
ZJS 数据流（PJL 头 + 分块图像）
  │  IOKit USB bulk write (endpoint 1)
  ▼
打印机
```

参数说明：

- `-r1200x600` — 1020 的引擎分辨率（横向 1200 dpi，纵向 600 dpi）
- `-p9` — A4 纸张（Letter 用 `-p1`）
- `-P` — 生成 PJL 作业头
- `-z1` — ZJS 模式

### USB 传输

`bin/hp1020_usb` 是一个小型 IOKit 工具，做两件事：

1. 推送固件到打印机 RAM
2. 发送 ZJS 原始数据流

```bash
./bin/hp1020_usb --info              # 读取设备 ID
./bin/hp1020_usb fw/sihp1020.dl      # 推固件
./bin/hp1020_usb --send job.zjs      # 发数据
```

实现要点（踩过的坑）：

- 枚举 `IOUSBHostInterface` 服务，再按注册表 `idVendor`/`idProduct` 过滤
- **不能**用 `IOServiceMatching` 的字典过滤 —— 父设备属性不会下传到接口节点
- `GetPipeProperties` 的参数必须是 `UInt16*`，传 `UInt8*` 会 bus error
- `GetPipeProperties` 返回 `0xe00002cd` 属正常，接口打开后仍可读写
- 裸引导态读到 `Got USB return aborted during read` 是正常现象

重新编译：

```bash
clang -O2 -framework Foundation -framework IOKit -framework CoreFoundation \
      -o bin/hp1020_usb src/hp1020_usb.m
```

---

## 故障排查

### 完全没动静，机器也不响

固件没跑起来。检查 `--status` 中的 FWVER 是否为 `20080222`。

### 设备从 USB 上消失了

```bash
ioreg -p IOUSB -w0 | grep -i laserjet   # 查不到
```

内核日志出现：

```
IOUSBHostDevice::getDescriptorGated: standard request timed out after 5000ms
failed to get device descriptor
IOUSBHostPort::disconnect: persistent enumeration failures
```

**原因**：推送了错误格式的固件（尤其是裸 ELF），把打印机的 USB 控制器搞进了异常态。端口被内核标记为"持续枚举失败"，不再自动重试，软件层面无法恢复。

**解法**：**拔掉电源线**（不是 USB 线），等 60 秒，只插回电源线等 30 秒自检，再插 USB。重启 macOS 也可以。

### 出纸但是白纸

固件版本错，或分辨率参数错。核对固件 md5，确认 `-r1200x600`。

### `USBInterfaceOpen: 0xe00002c5 (device busy?)`

有进程正占着设备（通常是 CUPS backend）。`sudo killall -9 cupsd` 后重试。

---

## 与 CUPS 的关系

本项目**不依赖 CUPS 队列**，直接走 USB 发送。

原因：CUPS 路径下若 filter 中途与固件加载竞争，容易造成 USB 通道锁死（`device busy`），且错误信息埋在日志里难排查。直发更可控。

如果你仍想用系统打印对话框，`install.sh` 会留下 Apple 官方 filter 所需组件，可自行配置。但推荐用 `hp1020-print`。

---

## 项目结构

```
hp1020-macos/
├── bin/hp1020_usb          IOKit USB 工具（arm64 预编译）
├── fw/sihp1020.dl          正确固件（128999 B，md5 0cd1ac3a...）
├── src/hp1020_usb.m        源码
├── scripts/hp1020-print    主脚本
├── vendor/                 第三方二进制（不进 Git，走 Release）
├── docs/                   补充文档
├── install.sh              安装
└── fetch-vendor.sh         下载 vendor 二进制
```

---

## 致谢

- [foo2zjs](https://github.com/OpenPrinting/foo2zjs) — ZJS 编码器（GPL v2）
- [Ghostscript](https://www.ghostscript.com/) — PDF/PS 渲染（AGPL v3）
- [Orthodox2000/hp-laserjet-1020-linux](https://github.com/Orthodox2000/hp-laserjet-1020-linux) — 固件格式陷阱的权威说明，本项目的固件校验值来源于此
- [anxkhn/hp1020-driver-mac](https://github.com/anxkhn/hp1020-driver-mac) — Apple 官方 filter 组件的整理

## 许可证

本项目代码 MIT。`fw/sihp1020.dl` 为 HP 专有固件，仅作兼容性用途分发。第三方组件遵循各自许可证。
