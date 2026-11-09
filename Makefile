# HP LaserJet 1020 on macOS
#
# 常用目标：
#   make            编译 hp1020_usb（universal binary）
#   make check      本地跑一遍 CI 的全部检查
#   make vendor     获取 Ghostscript 与 foo2zjs
#   make install    安装到 /usr/local
#   make test       检查固件格式
#   make clean      清理构建产物

SHELL := /bin/bash

ARCH := $(shell uname -m)
UNAME_S := $(shell uname -s)

BIN := bin/hp1020_usb
SRC := src/hp1020_usb.m

FRAMEWORKS := -framework Foundation -framework IOKit -framework CoreFoundation
CFLAGS := -O2 -Wall -Wextra

.PHONY: all build universal check vendor install test clean help

all: build

help:
	@echo "HP LaserJet 1020 on macOS"
	@echo
	@echo "  make build      编译当前架构"
	@echo "  make universal  编译 universal binary (arm64 + x86_64)"
	@echo "  make check      本地执行全部检查（无需 macOS 的 CI 等价物）"
	@echo "  make vendor     获取 Ghostscript 与 foo2zjs"
	@echo "  make install    安装到 /usr/local"
	@echo "  make test       检查固件格式"
	@echo "  make clean      清理产物"

build:
ifeq ($(UNAME_S),Darwin)
	@echo "==> 编译 $(ARCH)"
	clang $(CFLAGS) $(FRAMEWORKS) -o "$(BIN).$(ARCH)" "$(SRC)"
	@mv "$(BIN).$(ARCH)" "$(BIN)"
	@file "$(BIN)"
else
	@echo "当前不是 macOS，跳过编译。请在 Mac 上运行。"
endif

universal:
ifeq ($(UNAME_S),Darwin)
	@echo "==> 编译 arm64"
	clang $(CFLAGS) -arch arm64 $(FRAMEWORKS) -o /tmp/hp1020_arm64 "$(SRC)"
	@echo "==> 编译 x86_64"
	clang $(CFLAGS) -arch x86_64 $(FRAMEWORKS) -o /tmp/hp1020_x86_64 "$(SRC)"
	@echo "==> lipo 合并"
	lipo -create /tmp/hp1020_arm64 /tmp/hp1020_x86_64 -output "$(BIN)"
	@lipo -info "$(BIN)"
else
	@echo "当前不是 macOS，跳过编译。请在 Mac 上运行。"
endif

check:
	@bash scripts/selfcheck.sh

vendor:
	@./fetch-vendor.sh

install:
	@./install.sh

test:
	@./scripts/hp1020-fwinspect fw/sihp1020.dl

clean:
	rm -f "$(BIN).$(ARCH)" /tmp/hp1020_arm64 /tmp/hp1020_x86_64
	rm -rf scripts/__pycache__
	@echo "已清理"
