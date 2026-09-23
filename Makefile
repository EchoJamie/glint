APP_NAME     := Glint
VERSION      := 0.1.0

BUILD_DIR    := build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents

# 安装目录固定为 ~/Library/Input Methods/Glint.app（decisions.md 5.4）
INSTALL_DIR  := $(HOME)/Library/Input Methods

SOURCES_DIR  := sources
RESOURCES    := resources/Info.plist
LOCALIZATION := resources/zh-Hans.lproj

SOURCES      := $(wildcard $(SOURCES_DIR)/*.swift)

# Xcode 已安装时无需 sudo 切换 xcode-select，直接经 DEVELOPER_DIR 使用。
# 若只想用 CommandLineTools，执行 make DEVELOPER_DIR= （置空）。
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFTC        := DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun swiftc

# 只构建 Apple Silicon（arm64），不构建 Intel、不做通用二进制（D-14）
ARCH         := arm64
# 最低 macOS 版本尚未实测（D-14）。此处只是构建所需的形式值，
# 不代表已兼容该版本；实测结果记录到 TASKS.md 后再固定。
MIN_MACOS    := 13.0
TARGET       := $(ARCH)-apple-macos$(MIN_MACOS)

SWIFT_FLAGS  := -module-name $(APP_NAME) -parse-as-library -swift-version 5 \
                -target $(TARGET) -O

# 免费 Apple Development 证书，仅供本机开发与自用（D-15）。
# 无法用于向他人分发二进制——首版只发源码。
CODESIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
                  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)

.DEFAULT_GOAL := build
.PHONY: all build install uninstall clean check-ids deps help

all: build

help:
	@echo "make build     构建 $(APP_BUNDLE)（不安装）"
	@echo "make check-ids 核对 Info.plist 与 GlintIds.swift 的标识一致"
	@echo "make deps      下载固定版本的 librime 依赖"
	@echo "make install   安装到 $(INSTALL_DIR)（需显式执行，构建不会自动安装）"
	@echo "make uninstall 从 $(INSTALL_DIR) 移除，不动个人数据目录"
	@echo "make clean     清理构建产物"

# 标识一旦漂移会造成注册失败，且输入源 ID 变更会使系统内已注册的输入源失效，
# 因此在构建前强制核对（decisions.md 5.4）。
build: check-ids $(APP_BUNDLE)

check-ids:
	@bash scripts/check-ids.sh

$(APP_BUNDLE): $(SOURCES) $(RESOURCES) $(LOCALIZATION)/InfoPlist.strings
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	$(SWIFTC) $(SWIFT_FLAGS) -o $(CONTENTS)/MacOS/$(APP_NAME) $(SOURCES)
	@cp $(RESOURCES) $(CONTENTS)/Info.plist
	@cp -R $(LOCALIZATION) $(CONTENTS)/Resources/
	@plutil -lint $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@$(MAKE) --no-print-directory sign
	@echo "已构建：$(APP_BUNDLE)"

sign:
	@if [ -n "$(CODESIGN_ID)" ]; then \
		codesign --force --sign "$(CODESIGN_ID)" --timestamp=none $(APP_BUNDLE); \
		echo "已签名：$(CODESIGN_ID)"; \
	else \
		codesign --force --sign - $(APP_BUNDLE); \
		echo "⚠️  未找到 Apple Development 证书，已用 ad-hoc 签名（仅本机可运行）"; \
	fi

# 构建不隐式安装。启用输入源会改动用户系统状态，必须显式执行本目标。
install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "已安装到 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "下一步：$(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) --install"

# 只移除程序，不删除 ~/Library/Glint 下的个人数据（decisions.md §8 交付说明）
uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "已移除 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "个人数据目录未改动：~/Library/$(APP_NAME)"

deps:
	@bash scripts/fetch-librime.sh

clean:
	@rm -rf $(BUILD_DIR)
	@echo "已清理 $(BUILD_DIR)"
