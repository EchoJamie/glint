APP_NAME     := Glint

BUILD_DIR    := build
APP_BUNDLE   := $(BUILD_DIR)/$(APP_NAME).app
BUILD_STAMP  := $(BUILD_DIR)/.Glint-built
CONTENTS     := $(APP_BUNDLE)/Contents
FRAMEWORKS   := $(CONTENTS)/Frameworks

# 开发安装目录；正式安装器使用同一路径。
INSTALL_DIR  := $(HOME)/Library/Input Methods

SOURCES_DIR  := sources
RIME_DIR     := $(SOURCES_DIR)/rime
RESOURCES    := resources/Info.plist
RIME_DATA_READY := $(BUILD_DIR)/bundled-rime/.ready
RIME_DATA_ARCHIVE := $(BUILD_DIR)/bundled-rime.tar.gz
PREDICTION_DATA := deps/dist/share/glint/glint-predict.db
# 所有本地化目录都要进包。**英文那份不是可选的**：
# CFBundleDevelopmentRegion 是 en，且系统解析输入源显示名时可能按英文环境回退，
# 缺了 en.lproj 会拿 ID 原文当名字（见 resources/zh-Hans.lproj/InfoPlist.strings 的说明）。
LOCALIZATIONS := $(wildcard resources/*.lproj)
LOCALIZATION_FILES := $(wildcard resources/*.lproj/InfoPlist.strings)
# 图标由 scripts/make-icons.py 生成
# 输入源菜单图标（透明底矢量）与 app 图标（.icns）
ICON         := resources/glint.pdf
APP_ICON     := resources/GlintIcon.icns
# 签名用 entitlements；动态库嵌入后统一重签。
ENTITLEMENTS := resources/Glint.entitlements

SWIFT_SOURCES := $(wildcard $(SOURCES_DIR)/*/*.swift)
C_SOURCES     := $(wildcard $(RIME_DIR)/*.c)
C_OBJECTS     := $(patsubst $(RIME_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))

# 固定版本的 librime，由 scripts/fetch-librime.sh 取回
DEPS         := deps/dist
DEPS_READY   := $(DEPS)/lib/librime.dylib
RIME_PLUGINS := $(wildcard $(DEPS)/lib/rime-plugins/*.dylib)

# Xcode 已安装时无需 sudo 切换 xcode-select，直接经 DEVELOPER_DIR 使用。
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFTC        := DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun swiftc
CLANG         := DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun clang

# 只构建 Apple Silicon（arm64）。
ARCH         := arm64
# macOS 13.0 是编译目标，跨版本兼容仍需实机验证。
MIN_MACOS    := 13.0
TARGET       := $(ARCH)-apple-macos$(MIN_MACOS)

# 桥接头只暴露 glint_rime 这层封装，Swift 侧看不到 librime 的头文件。
# -I sources 让 #include "rime/glint_rime.h" 能解析。
SWIFT_FLAGS  := -module-name $(APP_NAME) -parse-as-library -swift-version 5 \
                -target $(TARGET) -O \
                -import-objc-header $(SOURCES_DIR)/BridgingHeader.h \
                -I $(SOURCES_DIR)

C_FLAGS      := -O2 -Wall -Wextra -fPIC -target $(TARGET) \
                -I $(DEPS)/include -I deps/yaml/include -I $(RIME_DIR)

# 依赖的 dylib 打进 bundle 的 Frameworks/，用相对 rpath 定位，
# 这样产物不依赖构建机上的绝对路径，可以被拷到别处运行。
LINK_FLAGS   := $(C_OBJECTS) deps/yaml/lib/libyaml.a -L $(DEPS)/lib -lrime \
                -Xlinker -rpath -Xlinker @executable_path/../Frameworks

# 本次交付固定使用约定的证书；证书缺失时构建失败。
CODESIGN_ID  := Apple Development: echojamieee@outlook.com (9JHY98AJMC)

.DEFAULT_GOAL := dmg
.PHONY: all build dmg sign icons embed-deps embed-licenses embed-rime-data bundle-rime install uninstall clean distclean check-ids deps help

all: dmg

help:
	@echo "make deps      取固定版本的 librime（scripts/fetch-librime.sh）"
	@echo "make           生成 Glint 0.1.0 DMG 交付包（不安装）"
	@echo "make build     构建内部 App（供 DMG 打包使用）"
	@echo "make dmg       显式重新生成 DMG 交付包"
	@echo "make icons     重新生成输入源图标"
	@echo "make bundle-rime  准备随包方案数据（使用基线包或 rime-ice 检出）"
	@echo "make check-ids 核对 Info.plist 与 GlintIds.swift 的标识一致"
	@echo "make install   用户级安装到 $(INSTALL_DIR)（需显式执行）"
	@echo "make uninstall 从 $(INSTALL_DIR) 移除，不动个人数据目录"
	@echo "make clean     清理构建产物（保留已下载的依赖）"
	@echo "make distclean 清理构建产物及 dist/ 交付包"

# 标识一旦漂移会造成注册失败，且输入源 ID 变更会使系统内已注册的输入源失效，
# 因此在构建前强制核对。
build: check-ids $(DEPS_READY) $(BUILD_STAMP)

dmg: build
	@bash scripts/package-dmg.sh

deps/yaml/lib/libyaml.a: scripts/fetch-libyaml.sh
	@bash scripts/fetch-libyaml.sh

check-ids:
	@bash scripts/check-ids.sh

$(DEPS_READY):
	@echo "缺少依赖，先取 librime："
	@$(MAKE) --no-print-directory deps

$(BUILD_DIR)/%.o: $(RIME_DIR)/%.c $(RIME_DIR)/glint_rime.h deps/yaml/lib/libyaml.a
	@mkdir -p $(BUILD_DIR)
	$(CLANG) $(C_FLAGS) -c $< -o $@

$(BUILD_STAMP): $(SWIFT_SOURCES) $(C_SOURCES) $(RIME_DIR)/glint_rime.h $(RESOURCES) Makefile $(RIME_DATA_ARCHIVE) $(LOCALIZATION_FILES) $(DEPS_READY) deps/yaml/lib/libyaml.a $(ICON) $(APP_ICON) $(ENTITLEMENTS) LICENSE THIRD_PARTY.md $(wildcard licenses/*.txt)
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources $(FRAMEWORKS)/rime-plugins
	@$(MAKE) --no-print-directory $(C_OBJECTS)
	$(SWIFTC) $(SWIFT_FLAGS) -o $(CONTENTS)/MacOS/$(APP_NAME) \
		$(SWIFT_SOURCES) $(LINK_FLAGS)
	@cp $(RESOURCES) $(CONTENTS)/Info.plist
	@for l in $(LOCALIZATIONS); do cp -R $$l $(CONTENTS)/Resources/; done
	@cp $(ICON) $(APP_ICON) $(CONTENTS)/Resources/
	@plutil -lint $(CONTENTS)/Info.plist
	@$(MAKE) --no-print-directory embed-licenses
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@$(MAKE) --no-print-directory embed-deps
	@$(MAKE) --no-print-directory sign
	@touch $(BUILD_STAMP)
	@echo "已构建：$(APP_BUNDLE)"

# librime 与三个插件的许可证必须随二进制一起分发——BSD-3-Clause 与 GPLv3
# 都要求保留版权声明与许可证正文。THIRD_PARTY.md 登记了组件与提交号。
embed-licenses:
	@mkdir -p $(CONTENTS)/Resources/licenses
	@cp licenses/*.txt $(CONTENTS)/Resources/licenses/
	@cp LICENSE THIRD_PARTY.md $(CONTENTS)/Resources/
	@echo "已随包附带 $(words $(wildcard licenses/*.txt)) 份第三方许可证"

# 方案资源缺失时直接中止构建，避免产出能启动却不能输入的 app。
$(PREDICTION_DATA): scripts/build-prediction-data.sh scripts/simplify-prediction.swift $(DEPS_READY)
	@bash scripts/build-prediction-data.sh

$(RIME_DATA_READY): scripts/bundle-rime-data.sh $(PREDICTION_DATA)
	@bash scripts/bundle-rime-data.sh

$(RIME_DATA_ARCHIVE): $(RIME_DATA_READY) Makefile
	@COPYFILE_DISABLE=1 /usr/bin/tar --no-xattrs --exclude=.ready -czf $@.tmp -C build/bundled-rime .
	@mv $@.tmp $@

embed-rime-data: $(RIME_DATA_ARCHIVE)
	@rm -rf $(CONTENTS)/Resources/rime
	@cp $(RIME_DATA_ARCHIVE) $(CONTENTS)/Resources/rime.tar.gz
	@cp build/bundled-rime/data-manifest.sha256 $(CONTENTS)/Resources/rime-manifest.sha256
	@echo "已嵌入压缩 Rime 方案数据与校验清单"

bundle-rime: $(PREDICTION_DATA)
	@bash scripts/bundle-rime-data.sh

# 把 librime 与插件打进 bundle，让产物不依赖构建机的绝对路径。
# 插件必须放在 Frameworks/rime-plugins/：librime 按自身位置找这个目录名。
embed-deps:
	@cp -f $(DEPS)/lib/librime.1.17.0.dylib $(FRAMEWORKS)/
	@ln -sf librime.1.17.0.dylib $(FRAMEWORKS)/librime.1.dylib
	@ln -sf librime.1.dylib $(FRAMEWORKS)/librime.dylib
	@cp -f $(RIME_PLUGINS) $(FRAMEWORKS)/rime-plugins/
	@echo "已嵌入 librime 与 $(words $(RIME_PLUGINS)) 个插件"

# **顺序要紧**：数据必须在签名之前嵌入。
# 签名封存的是整个 bundle 的资源清单，签名后再加文件会让签名失效
# （实测：codesign --verify 报 "a sealed resource is missing or invalid"）。
sign: embed-rime-data
	@set -e; \
	for lib in $(FRAMEWORKS)/librime.1.17.0.dylib $(FRAMEWORKS)/rime-plugins/*.dylib; do \
		if [ -f "$$lib" ]; then codesign --force --sign "$(CODESIGN_ID)" --timestamp=none "$$lib" >/dev/null; fi; \
	done; \
	codesign --force --options runtime \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(CODESIGN_ID)" --timestamp=none $(APP_BUNDLE); \
	echo "签名完成（Hardened Runtime + entitlements）"

# ------------------------------------------------------------------ 安装

# 构建不隐式安装。启用输入源会改动用户系统状态，必须显式执行本目标。
install: build
	@bash scripts/install-user.sh

# 只移除程序，不删除 ~/Library/Glint 下的个人数据。
uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "已移除 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "个人数据目录未改动：~/Library/$(APP_NAME)"

icons:
	@python3 scripts/make-icons.py

deps:
	@bash scripts/fetch-librime.sh

clean:
	@rm -rf $(APP_BUNDLE) $(BUILD_STAMP) $(BUILD_DIR)/*.o
	@echo "已清理构建产物"

distclean:
	@rm -rf $(BUILD_DIR) dist
	@echo "已清理 $(BUILD_DIR) 与 dist（交付包）"
