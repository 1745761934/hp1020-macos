# vendor/ — 第三方二进制

这两个文件体积较大（Ghostscript 约 37 MB），不放进 Git 仓库，通过 **GitHub Release** 分发。

`install.sh` 会在 `vendor/` 下查找它们；如果找不到，会尝试使用系统已安装的版本。

## 需要放置的文件

| 文件 | 大小 | md5 | 来源 |
|---|---|---|---|
| `vendor/gs-static` | 38584224 | `d385c594463badc19f3ae4f798a5f987` | Ghostscript 10.06.0，静态编译，arm64 |
| `vendor/foo2zjs` | 106952 | `059b96fc46e238a7add2f3b40d5c29a0` | foo2zjs（OpenPrinting），arm64 |

## 获取方式

### 方式 A — 从本仓库 Release 下载（推荐）

```bash
cd hp1020-macos
make vendor
```

或手动下载 Release 附件放到 `vendor/` 目录。

### 方式 B — 自己编译

**Ghostscript**

macOS 上没有预装 `gs`。可以用 Homebrew 装好后取二进制：

```bash
brew install ghostscript
cp "$(brew --prefix)/bin/gs" vendor/gs-static
```

注意 Homebrew 版是动态链接的，依赖 `libgs.dylib` 等库。若要真正静态可用，需自行编译：

```bash
curl -LO https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10060/ghostscript-10.06.0.tar.gz
tar xzf ghostscript-10.06.0.tar.gz && cd ghostscript-10.06.0
./configure --disable-compile-inits --without-x --disable-gtk
make -j$(sysctl -n hw.ncpu) sobin
cp bin/gs /path/to/vendor/gs-static
```

**foo2zjs**

```bash
git clone https://github.com/OpenPrinting/foo2zjs.git
cd foo2zjs
make
cp foo2zjs /path/to/vendor/foo2zjs
```

或直接从本机已安装的版本复制：

```bash
cp /usr/libexec/cups/filter/foo2zjs vendor/foo2zjs
```

## 许可证

- Ghostscript — AGPL v3
- foo2zjs — GPL v2

单独分发二进制时请遵守各自的许可证要求。
