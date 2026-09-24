APP_NAME     := Glint
VERSION      := 0.1.0

BUILD_DIR    := build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS     := $(APP_BUNDLE)/Contents
FRAMEWORKS   := $(CONTENTS)/Frameworks

# 安装目录固定为 ~/Library/Input Methods/Glint.app（decisions.md 5.4）
INSTALL_DIR  := $(HOME)/Library/Input Methods

# 隔离的测试数据目录。绝不复用 ~/Library/Rime。
TESTDATA     := $(BUILD_DIR)/testdata

SOURCES_DIR  := sources
RIME_DIR     := $(SOURCES_DIR)/rime
RESOURCES    := resources/Info.plist
LOCALIZATION := resources/zh-Hans.lproj
# 图标（均为 M0 占位版），由 scripts/make-icons.py 生成
# 输入源菜单图标（透明底矢量）与 app 图标（.icns）
ICON         := resources/glint.pdf
APP_ICON     := resources/GlintIcon.icns
# 签名用 entitlements。开启 Hardened Runtime 的前提，也是加载
# adhoc 签名的 librime 所必需的，见文件内说明。
ENTITLEMENTS := resources/Glint.entitlements

SWIFT_SOURCES := $(wildcard $(SOURCES_DIR)/*.swift)
C_SOURCES     := $(wildcard $(RIME_DIR)/*.c)
C_OBJECTS     := $(patsubst $(RIME_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))

# 固定版本的 librime（D-02），由 scripts/fetch-librime.sh 取回
DEPS         := deps/dist
DEPS_READY   := $(DEPS)/lib/librime.dylib
RIME_DYLIBS  := $(DEPS)/lib/librime.1.17.0.dylib
RIME_PLUGINS := $(wildcard $(DEPS)/lib/rime-plugins/*.dylib)

# Xcode 已安装时无需 sudo 切换 xcode-select，直接经 DEVELOPER_DIR 使用。
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFTC        := DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun swiftc
CLANG         := DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun clang

# 只构建 Apple Silicon（arm64），不构建 Intel、不做通用二进制（D-14）
ARCH         := arm64
# 最低 macOS 版本尚未实测（D-14）。此处只是构建所需的形式值，
# 不代表已兼容该版本；实测结果记录到 TASKS.md 后再固定。
MIN_MACOS    := 13.0
TARGET       := $(ARCH)-apple-macos$(MIN_MACOS)

# 桥接头只暴露 glint_rime 这层封装，Swift 侧看不到 librime 的头文件。
# -I sources 让 #include "rime/glint_rime.h" 能解析。
SWIFT_FLAGS  := -module-name $(APP_NAME) -parse-as-library -swift-version 5 \
                -target $(TARGET) -O \
                -import-objc-header $(SOURCES_DIR)/BridgingHeader.h \
                -I $(SOURCES_DIR)

C_FLAGS      := -O2 -Wall -Wextra -fPIC -target $(TARGET) \
                -I $(DEPS)/include -I $(RIME_DIR)

# 依赖的 dylib 打进 bundle 的 Frameworks/，用相对 rpath 定位，
# 这样产物不依赖构建机上的绝对路径，可以被拷到别处运行。
LINK_FLAGS   := $(C_OBJECTS) -L $(DEPS)/lib -lrime \
                -Xlinker -rpath -Xlinker @executable_path/../Frameworks

# 免费 Apple Development 证书，仅供本机开发与自用（D-15）。
CODESIGN_ID  ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
                  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)

.DEFAULT_GOAL := build
.PHONY: all build sign icons embed-deps embed-licenses seed-userdata install install-system uninstall clean distclean check-ids deps testdata selftest help

all: build

help:
	@echo "make deps      取固定版本的 librime（scripts/fetch-librime.sh）"
	@echo "make build     构建 $(APP_BUNDLE)（不安装）"
	@echo "make icons     重新生成输入源图标（M0 占位版）"
	@echo "make testdata  准备隔离的测试数据目录 $(TESTDATA)"
	@echo "make selftest  跑候选协议离线用例"
	@echo "make seed-userdata  把测试数据放进 ~/Library/Glint（开发用）"
	@echo "make check-ids 核对 Info.plist 与 GlintIds.swift 的标识一致"
	@echo "make install   用户级安装到 $(INSTALL_DIR)（需显式执行）"
	@echo "make install-system  系统级安装到 /Library/Input Methods/（需 sudo）"
	@echo "make uninstall 从 $(INSTALL_DIR) 移除，不动个人数据目录"
	@echo "make clean     清理构建产物（保留已下载的依赖）"

# 标识一旦漂移会造成注册失败，且输入源 ID 变更会使系统内已注册的输入源失效，
# 因此在构建前强制核对（decisions.md 5.4）。
build: check-ids $(DEPS_READY) $(APP_BUNDLE)

check-ids:
	@bash scripts/check-ids.sh

$(DEPS_READY):
	@echo "缺少依赖，先取 librime："
	@$(MAKE) --no-print-directory deps

$(BUILD_DIR)/%.o: $(RIME_DIR)/%.c
	@mkdir -p $(BUILD_DIR)
	$(CLANG) $(C_FLAGS) -c $< -o $@

$(APP_BUNDLE): $(SWIFT_SOURCES) $(C_SOURCES) $(RESOURCES) $(LOCALIZATION)/InfoPlist.strings $(DEPS_READY) $(ICON) $(APP_ICON) $(ENTITLEMENTS) LICENSE THIRD_PARTY.md $(wildcard licenses/*.txt)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(FRAMEWORKS)/rime-plugins
	@$(MAKE) --no-print-directory $(C_OBJECTS)
	$(SWIFTC) $(SWIFT_FLAGS) -o $(CONTENTS)/MacOS/$(APP_NAME) \
		$(SWIFT_SOURCES) $(LINK_FLAGS)
	@cp $(RESOURCES) $(CONTENTS)/Info.plist
	@cp -R $(LOCALIZATION) $(CONTENTS)/Resources/
	@cp $(ICON) $(APP_ICON) $(CONTENTS)/Resources/
	@plutil -lint $(CONTENTS)/Info.plist
	@$(MAKE) --no-print-directory embed-licenses
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@$(MAKE) --no-print-directory embed-deps
	@$(MAKE) --no-print-directory sign
	@echo "已构建：$(APP_BUNDLE)"

# librime 与三个插件的许可证必须随二进制一起分发——BSD-3-Clause 与 GPLv3
# 都要求保留版权声明与许可证正文。THIRD_PARTY.md 登记了组件与提交号。
embed-licenses:
	@mkdir -p $(CONTENTS)/Resources/licenses
	@cp licenses/*.txt $(CONTENTS)/Resources/licenses/
	@cp LICENSE THIRD_PARTY.md $(CONTENTS)/Resources/
	@echo "已随包附带 $(words $(wildcard licenses/*.txt)) 份第三方许可证"

# 把 librime 与插件打进 bundle，让产物不依赖构建机的绝对路径。
# 插件必须放在 Frameworks/rime-plugins/：librime 按自身位置找这个目录名。
embed-deps:
	@cp -f $(DEPS)/lib/librime.1.17.0.dylib $(FRAMEWORKS)/
	@ln -sf librime.1.17.0.dylib $(FRAMEWORKS)/librime.1.dylib
	@ln -sf librime.1.dylib $(FRAMEWORKS)/librime.dylib
	@cp -f $(RIME_PLUGINS) $(FRAMEWORKS)/rime-plugins/ 2>/dev/null || true
	@echo "已嵌入 librime 与 $(words $(RIME_PLUGINS)) 个插件"

sign:
	@if [ -n "$(CODESIGN_ID)" ]; then \
		IDENT="$(CODESIGN_ID)"; \
	else \
		IDENT="-"; \
		echo "⚠️  未找到 Apple Development 证书，改用 ad-hoc 签名（仅本机可运行）"; \
	fi; \
	for lib in $(FRAMEWORKS)/*.dylib $(FRAMEWORKS)/rime-plugins/*.dylib; do \
		[ -f "$$lib" ] && codesign --force --sign "$$IDENT" --timestamp=none "$$lib" >/dev/null 2>&1; \
	done; \
	codesign --force --options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$$IDENT" --timestamp=none $(APP_BUNDLE); \
	echo "已签名：$$IDENT（Hardened Runtime + entitlements）"

# ------------------------------------------------------------------ 测试数据

# 隔离的测试数据目录：从参考仓库的 rime-ice 建一份，不动 ~/Library/Rime。
testdata: $(TESTDATA)/rime

$(TESTDATA)/rime:
	@bash scripts/setup-testdata.sh

selftest: build testdata
	@$(CONTENTS)/MacOS/$(APP_NAME) --selftest $(TESTDATA)

# ------------------------------------------------------------------ 安装

# 构建不隐式安装。启用输入源会改动用户系统状态，必须显式执行本目标。
install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "已安装到 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "下一步：$(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME) --install"

# 系统级安装到 /Library/Input Methods/（需 sudo）。用于验证「是否因为装在
# 用户级目录才需要注销」——参考实现鼠须管用的是系统级路径。见 TASKS.md §0。
install-system: build
	@bash scripts/install-system.sh

# 只移除程序，不删除 ~/Library/Glint 下的个人数据（decisions.md §8）
uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "已移除 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "个人数据目录未改动：~/Library/$(APP_NAME)"

icons:
	@python3 scripts/make-icons.py

# 开发用：让已安装的输入法能真正出候选。不是产品的首次部署方式，
# 也尚未固定方案版本，理由见 scripts/seed-userdata.sh 的说明。
seed-userdata: testdata
	@bash scripts/seed-userdata.sh

deps:
	@bash scripts/fetch-librime.sh

# 保留测试数据：重建一次要拷 50 MB，而它与构建产物无关。
clean:
	@rm -rf $(APP_BUNDLE) $(BUILD_DIR)/*.o
	@echo "已清理构建产物（保留 $(TESTDATA)）"

# 连测试数据一起删。
distclean:
	@rm -rf $(BUILD_DIR)
	@echo "已清理 $(BUILD_DIR)（含测试数据）"
