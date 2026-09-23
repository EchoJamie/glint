# 流光 / Glint

macOS 中文输入法。以 [Rime/librime](https://github.com/rime/librime) 为引擎，候选体验参照 macOS 原生简体拼音，提供连续滚动的**卷轴候选**、原生风格 **Touch Bar** 候选、可视化设置与词库管理。

- 第一目标：作者本人在 Mac 上长期使用。
- 第二目标：公开在 GitHub，允许他人获取、使用、修改和分享。无商业化计划，也不额外设置用途限制。
- 当前状态：**尚未开始开发**。需求、功能方案与实施计划已形成，即将进入 M0 技术原型。

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/decisions.md](docs/decisions.md) | 决策记录：目标与使用背景、已确定方向（D-01–D-15）、职责边界、许可证与未决事项。 |
| [docs/native-candidate-interaction.md](docs/native-candidate-interaction.md) | 卷轴候选与 Touch Bar 的功能与交互方案：窗口状态、排布、按键、Rime 接入与验收清单。 |
| [docs/implementation-plan.md](docs/implementation-plan.md) | 实施计划：M0–M5 阶段、依赖关系、首版范围、验收条件与投入估算。 |
| [TASKS.md](TASKS.md) | 任务清单。实施计划的执行视图，记录当前阶段可勾选项、状态与证据。 |
| [THIRD_PARTY.md](THIRD_PARTY.md) | 第三方组件、固定提交号与许可证登记；许可证正文在 [licenses/](licenses/)。 |

上述文档中的**技术组织、设置清单、格式范围和工期属于执行默认值**，不等同于已经逐项确认的需求；需求以 decisions.md 与 native-candidate-interaction.md 为准。

## 项目标识

| 字段 | 值 |
| --- | --- |
| 中文名 | 流光 |
| 英文名 / Executable | `Glint` |
| CFBundleIdentifier | `com.github.echojamie.glint` |
| 输入源 ID | `com.github.echojamie.glint.Hans` |
| InputMethodConnectionName | `Glint_Connection` |
| InputMethodServerControllerClass | `Glint.GlintInputController` |
| 安装目录 | `~/Library/Input Methods/Glint.app` |
| 用户数据目录 | `~/Library/Glint`（与 `~/Library/Rime` 同构，完全独立、不共享） |
| 起始版本号 | `0.1.0` |

只做简体输入源。平台范围锁定 **Apple Silicon（arm64）**，不构建 Intel、不做通用二进制；最低 macOS 版本待 M0/M1 实测后记录。

## 构建与安装

需要 Xcode 与 `make`。Xcode 已安装时无需 `sudo xcode-select`——`Makefile` 通过 `DEVELOPER_DIR` 直接使用它。

```sh
make deps      # 取固定版本的 librime 1.17.0 到 deps/dist/（校验和核对）
make build     # 产出 build/Glint.app，不安装
make selftest  # 候选协议离线用例（自动准备隔离测试数据）
make install   # 复制到 ~/Library/Input Methods/，须显式执行
```

`make deps` 与 `make testdata` 取回或生成的内容都在 `.gitignore` 内，可随时删除重建。
librime 与三个插件会嵌入 `Contents/Frameworks/`，产物不依赖构建机的路径。

构建与安装是分开的两步，`make build` **不触碰系统**。安装后还需向系统注册输入源：

```sh
"$HOME/Library/Input Methods/Glint.app/Contents/MacOS/Glint" --install
```

`make uninstall` 只移除程序，不删除 `~/Library/Glint` 下的个人数据——卸载程序与删除个人数据是两件事。

只构建 Apple Silicon（arm64），不构建 Intel、不做通用二进制。

> **当前状态**：M0。librime 已接入并嵌入产物，候选协议通过 19/19 离线用例
> （`make selftest`），但**尚不能输入汉字**——输入控制器对按键一律透传，
> 这条链路还没接上，因此即便启用也不会打断正常打字。
> 候选窗口与 Touch Bar 未开始。见 [TASKS.md](TASKS.md)。

首版**只发布源码，不发布二进制**。签名使用免费 Apple Development 证书，仅适用于本机开发与自用；向他人分发二进制需要 `Developer ID Application` 证书（仅付费账号可得）。需要安装包的人自行构建。

## 许可证

本项目按 [GPLv3](LICENSE) 发布：`Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>`。

复用的第三方组件保留其原有许可证与署名，来源与许可见 [docs/decisions.md 第 5 节](docs/decisions.md)。librime 为 BSD-3-Clause，Squirrel 为 GPLv3。
