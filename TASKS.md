# 任务清单

- 日期：2026-09-24
- 状态：**M0 进行中，已首次安装**。librime 1.17.0 已接入并嵌入产物，
候选协议（全局索引读取 / 高亮 / 确认）与真实按键路径已通过 **28/28** 离线用例。
输入控制器已接上引擎（预编辑 + 提交），**但从未在真实输入会话里跑过**——
首次安装后需要注销重新登录，见 §0。候选窗口与 Touch Bar 未开始。
- 权威来源：[实施计划](docs/implementation-plan.md)（阶段、依赖、范围、验收、估算）、[功能方案](docs/native-candidate-interaction.md)（候选与 Touch Bar 交互契约）。
- 本文件是**执行视图**：把阶段拆成可勾选的任务，记录状态、交付物与实际证据。
- 勾选规则：只勾选**有证据**的任务。写入文件、构建"能编译"、在一台设备上显示成功，都不等于对应验收项已通过（[实施计划 §7](docs/implementation-plan.md#7-验证与试用安排)）。

## 0. 当前阻塞：需要重新登录

**2026-09-24，首次安装。** 已完成 `make install` 与 `Glint --install`，
但**系统在当前登录会话里还没有扫描到这个输入源**，需要注销并重新登录。

| 检查项 | 结果 |
| --- | --- |
| `make install` 复制到 `~/Library/Input Methods/Glint.app` | ✅ |
| 安装后 `codesign --verify --strict` | ✅ 通过 |
| `TISRegisterInputSource` 返回值 | ✅ `noErr` |
| 系统 TIS 列表中是否出现 | ❌ 331 个输入源中无 glint |
| 重启 `TextInputMenuAgent` / `TextInputSwitcher` / `imklaunchagent` | ❌ 无效 |
| `launchctl kickstart` | ❌ SIP 拦截（Operation not permitted） |
| `open` 让 launchd 拉起已安装的 app | ✅ 进程起来，但注册仍不生效 |

**🔍 原因已查明（2026-09-25，有完整日志证据）。**

`TISRegisterInputSource` 内部会**同步**向 tccd 查一次
**输入监控（Input Monitoring / kTCCServiceListenEvent）** 权限；被拒则注册不生效。
同一进程内的完整往返：

```
Glint (TCC) TCCAccessRequest() IPC
Glint SEND: function=TCCAccessRequest, service=kTCCServiceListenEvent
Glint RECV: { "prompt_type" => 1, "do_not_cache" => true,
              "auth_value" => 0, "result" => false, "auth_reason" => 4 }
```

**关键在归责链**：TCC 把这个请求归责给**发起进程的 responsible process**：

```
responsible={ identifier=com.mitchellh.ghostty, ... }        ← 我们的终端
requesting ={ identifier=com.github.echojamie.glint, ... }
```

从终端运行 `--install`，归责对象就是终端；终端没有输入监控权限，请求被拒，
而且弹窗也是弹给终端的。**因此「从终端注册」这条路永远走不通**，与我们的
bundle 无关。

**这解释了鼠须管为什么没有这个问题**：它是 `.pkg` 的 postinstall 发起注册，
不经过终端。同理，**登录时输入法由系统直接拉起，归责链也不经过终端**。

**已排除的原因**（每一项都实测过，不是推测）：安装位置（用户级/系统级）、
注册身份（登录用户/ root）、LaunchServices 登记、`Info.plist` 结构（与解包后的
Squirrel 逐键比对）、签名方式（补上 Hardened Runtime 与 entitlements 后仍然如此）。

**⚠️ 因果链不完整（2026-09-25 更新）**：用户给 Glint 授予输入监控、并以终端身份
重跑注册后，日志显示 TCC **已经通过**：

```
03:00:17  auth_value => 2, result => true      ← 已授予
```

**但输入源依然不出现在 TIS 列表里。** 重启 `TextInputMenuAgent` /
`TextInputSwitcher` / `imklaunchagent` 也无效。

因此 **TCC 是一道真实的门（此前确实被它挡住），但不是全部**——过了它之后还有
尚未查明的一环。此前把它当成完整原因，是把「已排除的障碍」误当成「唯一原因」。

**同时确认**：本机没有任何第三方 IME 可作对照——TIS 列表里的 11 个
`TISTypeKeyboardInputMethodModeEnabled` 全部是苹果自家的。

**剩下的可能**：签名身份（鼠须管用付费的 Developer ID Application，我们用免费的
Apple Development，D-15）；或系统在建登录会话时扫描输入法目录，运行时注册的
不进入当前会话。

**下一步二选一**：注销重登（此时 TCC 已授权，条件齐备）；
或先装鼠须管做对照，判断「是不是任何第三方 IME 在这台机器上都注册不了」。

以下是此前的排查记录：

**已实测确认归责链是症结（此结论现已被上面推翻）**：给 **Glint 本身**授予输入监控后，从终端注册**仍然被拒**——
TCC 判的是 responsible process：

```
responsible = com.mitchellh.ghostty      ← 终端
accessing   = com.github.echojamie.glint
```

也就是说，从终端注册这条路，**给谁授权都没用，除非给终端授权**。

**可行的两条路**：
1. 给终端（Ghostty）授予「输入监控」——开发期绕道，代价是终端拿到一个很宽的权限；
2. **注销重新登录**——归责链变成系统直接拉起输入法。这是产品实际会走的流程。

**产品事实（需写进安装说明）**：`TISRegisterInputSource` 硬性检查输入监控权限，
因此**安装 Glint 需要用户授予该权限**，不是把 app 拷过去就行。

**与 decisions.md 里那条的区别**：decisions.md 3 写「尚未决定引入全局键盘监听」，
那说的是**我们自己**装监听器；这里说的是**系统要求输入法本身**具备该权限。
两件事必须分开记，不要合并成一条。

**附带发现**：我们的签名此前**没有 Hardened Runtime、也没有任何 entitlements**，
而鼠须管两者皆有。已补齐 `resources/Glint.entitlements`
（`disable-library-validation` + `app-sandbox=false`）并开启 Hardened Runtime——
前者本来就必需，因为打进包的 librime 是 adhoc 签名。

**排查过程中的一个陷阱**：`log` 是 **zsh 的内建命令**（列出登录用户），
直接写 `log show ...` 不会报错但什么都不执行。此前几次「日志查询无结果」
因此全是假的，白绕了几轮。查询系统日志要用 `/usr/bin/log`。

以下是此前的修订记录：

**⚠️ 结论已修订（2026-09-25）。** 之前把「需要注销」当作 macOS 的固定行为收工，
是**过早结论**。用户指出：安装鼠须管时并未注销，装完即生效。

查参考实现后找到关键差异：

```
Squirrel/Makefile:  DSTROOT = /Library/Input Methods
                    SQUIRREL_APP_ROOT = $(DSTROOT)/Squirrel.app
postinstall:        sudo -u <登录用户> --register-input-source
                    sudo -u <登录用户> --enable-input-source
```

**鼠须管装在系统级 `/Library/Input Methods/`，从未用过用户级路径。**
而本项目按 [decisions.md 5.4](docs/decisions.md#54-项目标识版权与签名) 装在
`~/Library/Input Methods/`。路径不同很可能就是差异所在。

`make install-system` 用于验证（需 sudo）。**结果出来之前，
「是否需要注销」保持未定，不再当作已确认的事实。**

**重新登录后要做的事**

```sh
G="$HOME/Library/Input Methods/Glint.app/Contents/MacOS/Glint"
"$G" --list-input-sources glint     # 应列出 com.github.echojamie.glint.Hans
"$G" --enable-input-source          # 启用
```

然后切换到「流光」输入源，在文本编辑器里输入 `nihao`。**预期**：出现下划线预编辑
文本，空格或数字键上屏候选。这条链路已经接好并离线验证过（`make selftest`），
但**从未在真实输入会话里跑过**——本机第一次。

观察诊断输出：`scripts/run-dev.sh`（优先运行已安装副本并收集 stderr）。

**数据已就位**：`~/Library/Glint` 已用 rime-ice 播种并可正常部署
（`--selftest ~/Library/Glint` 通过 28/28）。这是**开发手段**，不是产品的首次部署
方式——随包附带方案数据属 M1，且方案版本尚未固定，见 §1.1。移除：`rm -rf ~/Library/Glint`。

**若登录后仍未出现**，下一步试系统级安装（需 sudo，且位置与
[decisions.md 5.4](docs/decisions.md#54-项目标识版权与签名) 定的用户级目录不同，
属需要一并确认的偏离）：参考实现鼠须管装的是 `/Library/Input Methods/Squirrel.app`，
并注明需要 sudo。用户级目录理论上受支持（该目录本就存在且带 `.localized`），
但本机未能验证。

**当前系统状态**：已安装、未注册生效、**未改动任何现有输入源设置**。
系统偏好里仍只有原来的 ABC，`AppleEnabledInputSources` 中没有 glint。
回退方式：`make uninstall`。

## 1. 环境前置核对（2026-09-24 实测）

开工前对本机做了一次只读核对。结果与文档中假定的环境**不一致**，直接改变 M0 的可执行范围。

| 检查项 | 实测结果 | 影响 |
| --- | --- | --- |
| 硬件 | Mac mini `Mac17,16`，Apple M5 Pro，64 GB | ⚠️ **无实体 Touch Bar**，T0.4 实机验收在本机无法完成 |
| **输入设备** | 本机**无直连键盘**（IOKit 查询为 0）；键鼠经**通用控制**来自 `Jamie's MacBook Pro` | 🔴 见 §3.0：所有按键都是远程注入，测出的行为不等于本地键盘 |
| 鼠须管 App | 未安装：`/Library/Input Methods/` 与 `~/Library/Input Methods/` 下均无 `Squirrel.app` | 🔴 见下 |
| `~/Library/Rime` | **不存在** | 🔴 无法在本机取得 D-03 的体验基线（全拼方案、词库、插件组合） |
| 参考仓库 clone | ✅ 2026-09-24 已 clone 并固定，见 §1.1 | 计划 §3 的 10 个复用文件全部存在 |
| rime-ice 词库 | ⚠️ 本机 clone 的是**今天 main**（`9e66b072`），非实际使用版本 | 需从另一台机器反查实际版本后再固定 |
| iCloud Drive | `~/Library/Mobile Documents/com~apple~CloudDocs` 存在 | ✅ T0.1 的 iCloud 只读探查可开展 |
| `.icloud` 占位文件 | 顶层未发现 | ✅ 与 [decisions.md 3.2](docs/decisions.md#32-icloud-同步) 记录一致；实现仍须处理 |
| 签名证书 | `Apple Development: echojamieee@outlook.com (9JHY98AJMC)`，1 个有效身份 | ✅ 与 D-15 一致 |
| Xcode | `Xcode.app` 已安装，但 `xcode-select` 指向 CommandLineTools | 🟡 需 `sudo xcode-select -s /Applications/Xcode.app` 才能建 .app 与 InputMethodKit 工程 |
| macOS SDK | `27.0`（CommandLineTools） | 最低系统版本仍待实测（D-14） |
| Git 身份 | 本机无全局 git 配置 | ✅ 已在本仓库设为 `EchoJamie <echojamieee@outlook.com>`，仅本仓库生效 |
| 仓库名 | 本目录为 `glint`；D-13 定的仓库名是 **`glint-ime`** | 🟡 创建远端时按 `glint-ime`，或先统一本地目录名 |

### 1.1 参考仓库与方案数据（2026-09-24 已就位）

全部放在 glint **之外**，按 D-04 保持参考用途，不进入本仓库、不作为交付物。

| 路径 | 内容 | 固定版本 |
| --- | --- | --- |
| `/Users/echo/namespace/github/rime/squirrel` | 参考实现。计划 §3 列出的 10 个复用文件**已逐一确认存在**（`SquirrelInputController.swift` 642 行等） | `0cd71a6130a5866b0ae6ba0494929ebdc8211194` |
| `/Users/echo/namespace/github/rime/rime-ice` | 雾凇拼音方案与词库。`cn_dicts/` 共 **1,919,066** 条词条 | ⚠️ `9e66b072`（今天 main，非实际使用版本） |

**librime 构建方式**（摘自 Squirrel Makefile，供 T0.1 参考）：`make -C librime deps` → `make -C librime release install`，产出 `librime/dist/lib/librime.1.dylib` 与 `rime-plugins/`。子模块钉在 `33e78140250125871856cdc5b42ddc6a5fcd3cd4`，与 D-02 锁定的 1.17.0 一致。

**🔴 基线缺口**：D-03 要求「将当前可接受的全拼方案和词库组合视为体验基线」，T0.1 要求「记录实际使用的全拼方案及必要插件」。方案源码可以从 GitHub 拿到，但**下面两项拿不到**：

1. 实际使用的 rime-ice **版本**——文档从未记录，本机 clone 的是今天 main，与用户实际部署的不是同一份。
2. 用户在 `~/Library/Rime` 下对方案做过的 `*.custom.yaml` 改写——这部分不在任何公开仓库里。

**取证方式**：另一台 Mac 上把 `~/Library/Rime` 打成一包，**排除 `build/` 与 `*.userdb/`**，体积约几百 KB。个人学习词条不进这个包（那是 M4 迁移的事），因此不涉及个人输入内容外传。

T0.1 不必等它——最小原型可以先跑通；但"固定基线"这一条在拿到该包之前不能勾选。

## 2. M0：技术原型

**阶段通过条件**（[实施计划 §4](docs/implementation-plan.md#4-阶段依赖与退出条件)）：能从真实 Rime 会话取得候选，屏幕与触控栏选择回到同一引擎；确定能满足卷轴的窗口路径。粗估 2–4 个开发日；桥接受阻单独重估。

M0 使用固定测试候选和**隔离的 Rime 数据目录**，不对任何现有 `~/Library/Rime` 做维护。

---

### [~] T0.1 基线与独立原型　—— **骨架与依赖就位；基线与最低系统版本待实测**

**已完成（2026-09-24）**

- 独立工程骨架，标识全部使用 [decisions.md 5.4](docs/decisions.md#54-项目标识版权与签名) 的已定值，无占位名。
- 所有源文件头已写入 `Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>` 与 GPLv3 声明。
- **构建与安装分离**：`make build` 只产出 `build/Glint.app`，不触碰系统；`make install` 才复制到 `~/Library/Input Methods/`，需显式执行。
- 只构建 arm64，产物经 `lipo` 确认非通用二进制（D-14）。
- 用免费 Apple Development 证书签名，`codesign --verify --strict` 通过（D-15）。
- 输入源注册 / 启用 / 停用 / 切换的命令行入口已实现（尚未执行）。
- **图标已有 M0 占位版**，由 `scripts/make-icons.py` 手写 PDF 生成，不引入图形库：
  输入源菜单用 `resources/glint.pdf`（透明底黑色四角星，16 px 下可辨认，
  系统会按明暗自动着色）；app 图标用 `resources/GlintIcon.icns`
  （深蓝底白色四角星，经 sips + iconutil 生成），已确认被系统接受。
  正式图标仍是 M1 前交付项。**注意**：这里没有走 Asset Catalog——
  直接给 .icns 更简单，代价是少了明暗与可访问性变体。
- librime 1.17.0 依赖已按固定版本取回并校验和核对（`make deps`），含 lua / octagram / predict 三个插件。
- **来源与许可已登记**：`THIRD_PARTY.md` 记录各组件、固定提交号与许可证，正文在 `licenses/`，
  并随包附带到 `Contents/Resources/`。把 dylib 打进产物就产生了保留声明的义务，
  不是可选项。核对时发现 **GitHub 的 license API 把 librime-octagram 误报为 BSD-3-Clause，
  其 `LICENSE` 正文实为 GPLv3**——登记按文件正文，不采信分类器。

**尚未完成**

- 「记录实际使用的全拼方案及必要插件」**受阻**，见 §1 基线缺口，需从另一台 Mac 导出。
- 最低 macOS 版本未实测：`Makefile` 里的 `13.0` 只是构建所需的形式值，**不构成兼容承诺**（D-14）。

**交付物**

- [x] 构建成功的最小输入法产物（`make build`，产物可启动、可签名校验）
- [x] 依赖与环境清单——librime 固定版本、工具链、许可证已记录（§1、§1.1、THIRD_PARTY.md）
- 🟡 最低 macOS 版本仍未实测（D-14）：`Makefile` 里的 `13.0` 只是形式值
- [x] 构建步骤与安装步骤分离，可重复执行

**顺带核实**（只读探查，不建立同步逻辑）

- [~] 非沙盒进程读写 `~/Library/Mobile Documents/com~apple~CloudDocs` 是否触发系统授权提示：
  已在 Terminal 上下文测过（目录可读、1 ms、无阻塞），但 TCC 上下文取决于启动者，
  **真实结论需在输入法上下文里复测**（`Glint --probe-icloud`）
- [ ] 未下载的 `.icloud` 占位文件在读写时的实际表现 —— **本机云盘内不存在这类文件，无法验证**

**工程结构**

```text
Makefile                  build / install / deps / testdata / selftest / check-ids / uninstall
sources/GlintIds.swift    标识常量（Swift 侧唯一来源）
sources/Main.swift        进程入口：带参数执行安装命令，不带参数常驻为输入法服务
sources/GlintInputController.swift   系统输入接入层（已接引擎：会话、预编辑、提交）
sources/InputSourceInstaller.swift   输入源注册 / 启用 / 停用 / 切换
sources/ICloudProbe.swift   iCloud Drive 只读探查
sources/RimeEngine.swift   librime 的 Swift 封装（会话、候选、确认）
sources/SelfTest.swift     候选协议离线用例
sources/MacOSKeyCodes.swift  macOS 键码 → librime 键码（复用自鼠须管）
sources/BridgingHeader.h   只暴露 glint_rime，不暴露 rime_api.h
sources/rime/glint_rime.{h,c}         librime C API 桥接层
resources/Info.plist      系统读取的标识定义
resources/zh-Hans.lproj/  中文名「流光」的本地化
licenses/                 第三方许可证正文
THIRD_PARTY.md            组件、提交号与许可证登记
scripts/check-ids.sh      构建前核对 Info.plist 与 GlintIds.swift 的标识一致
scripts/fetch-librime.sh  按固定版本 + 校验和取 librime
scripts/setup-testdata.sh 建立隔离测试数据，拒绝写入 ~/Library/Rime
scripts/make-icons.py     生成输入源图标 PDF 与 app 图标 icns（M0 占位版）
scripts/run-dev.sh        前台运行并收集诊断输出，供 T0.3 观察会话事件
scripts/seed-userdata.sh  把测试数据放进 ~/Library/Glint（开发用，非产品部署方式）
```

**关于 Xcode**：本机 `xcode-select` 指向 CommandLineTools，但 `Makefile` 通过 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 直接使用已安装的 Xcode 27.0，**无需 sudo 切换**。

**设计取舍**：输入控制器已接引擎，但 `Command` 组合键一律不拦，认不出的键原样交回宿主。
引擎未处理的键也暂时交回——「组合进行中是否应该拦截」属于 T0.3 按键路由验证的内容，
在拿到真实会话结果前不预设。

---

### [~] T0.2 候选协议　—— **协议已接通并验证，代次机制未实现**

**实现**：`sources/rime/glint_rime.{h,c}`（C 桥接）+ `sources/RimeEngine.swift`（Swift 封装）。

C 层的存在理由是两条：把 librime 的函数指针表与手工内存管理关在一个文件里；
不把 `rime_api.h` 暴露给 Swift——桥接头只暴露 `glint_rime.h`，会话用不透明的
`int64_t` 表示，Swift 侧既不需要 librime 的头文件路径，也碰不到 `RIME_STRUCT_INIT`
那类东西。候选文本一律**复制**出来再交给调用方，因为迭代器一旦推进文本缓冲即失效
（功能方案 §6.3 对参考实现的说明）。

**离线用例**：`make selftest`，源码在 `sources/SelfTest.swift`。

**键码映射已接通并纳入用例**：`sources/MacOSKeyCodes.swift` 复用自鼠须管
（GPLv3，已在 [THIRD_PARTY.md](THIRD_PARTY.md) 登记来源、提交与修改）。
用例现在走**真实路径** —— macOS 虚拟键码 → 映射 → 引擎，因此映射表本身也在覆盖内。
`T0` 一节定点核对了 9 个键码（字母/空格/回车/Escape/删除/方向键/数字）。

**踩到的第二个坑**：librime 的 `key_table.h`（提供 `XK_*` 与修饰键掩码）
**不在官方预编译包内**，且它 `#include <X11/keysym.h>` —— macOS 不自带 X11。
因此本项目按值复述了需要的常量，取值来自 X11 `keysymdef.h`，
掩码值已逐项对照 `key_table.h` 的 `RimeModifier` 核实。

**2026-09-24 实测结果**（隔离测试数据，rime-ice，`通过 28/28，另有 1 项未覆盖`）

| 用例 | 结果 |
| --- | --- |
| **键码映射定点核对**（9 项：字母/空格/回车/Escape/删除/方向键/数字） | ✅ |
| 部署完成 / 会话可创建 | ✅ |
| 按键被引擎接收 | ✅ 5/5 |
| 读到候选 | ✅ 30 项，真实候选（你好 / 👋 / 拟好 / 你 / 尼） |
| 引擎高亮索引可用 | ✅ |
| 按全局索引单项重读一致 | ✅ 核对 30 项，批量读与单项读完全一致 |
| **连续读取超过单批** | ✅ 批次压到 5，读到 **87** 项 |
| **连续读取超过引擎一页** | ✅ 87 项，说明读的不是「引擎当前页」 |
| 全局索引连续无空洞 / 无重复 | ✅ |
| 确认后取到提交 | ✅ 「你好」 |
| 提交不被重复消费 | ✅ 第二次为空 |
| 长输入产生候选 | ✅ 31 项 |
| 局部确认后状态自洽 | ✅ 提交「你好世界」，无残留编码 |
| 局部确认不产生第二次提交 | ✅ |
| 失效会话读取报失败（而非「没有了」） | ✅ |
| 失效会话选择 / 高亮被拒绝 | ✅ |
| 同字不同候选身份可区分 | ⚠️ **未覆盖**——本方案不返回注释，该场景不存在 |

**产物自包含**：librime 与三个插件嵌入 `Contents/Frameworks/`，
用 `@executable_path/../Frameworks` 定位。**移走 `deps/` 后用例仍全部通过**，
确认产物不依赖构建机的绝对路径。

**踩到的坑（值得记住）**

1. librime 的 `process_key` 收的是 **IBus / X11 键码**，不是 macOS 虚拟键码。
   直接传 `NSEvent.keyCode`（`n`=45）会被引擎当成别的字符，表现为「部分按键被接收」
   这种难查的现象。小写字母要用 ASCII 值（`n`=110）。
2. librime 的 `key_table.h`（提供 `XK_*` 与修饰键掩码）**不在官方预编译包内**，
   且它 `#include <X11/keysym.h>`——macOS 不自带 X11。本项目按值复述所需常量，
   取值来自 X11 `keysymdef.h`，掩码值逐项对照 `key_table.h` 的 `RimeModifier` 核实。

映射表已按计划 §3 复用参考实现并纳入用例（`sources/MacOSKeyCodes.swift`，
来源与修改见 [THIRD_PARTY.md](THIRD_PARTY.md)），不再是待办。

**尚未完成**

- **候选代次机制未实现。** 功能方案 §6.3 要求输入、拼音光标、待转换分段、会话
  变化时递增代次使旧缓存与旧事件失效。目前只有会话有效性检查（`find_session`），
  够用例用，但不够 UI 用——没有消费者之前先不建这套状态。
- `glint_rime_process_key` 之外的按键路径（组合光标移动、方案切换）未接。
- 一个良性警告：`rime.lua should be either in the rime user data directory or in
  the rime shared data directory`。这份 rime-ice 顶层没有 `rime.lua`，其 lua 功能
  走 `lua/` 目录直接引用，不影响候选生成。

**交付物**

- [x] 能检查候选身份及提交次数的离线用例
- [x] 不使用真实个人词条作测试样本（数据来自公开的 rime-ice，且目录隔离）
- [ ] 同字不同候选的覆盖——需要一份带注释的方案数据，见上表

---

### [ ] T0.3 公共候选窗口

**具体工作**：用同一组长短候选，在真实 Rime 会话上核对公开 `IMKCandidates` 能否承担屏幕窗口。逐项记录成功/失败，不预设结论。

| 验证条件 | 通过标准 | 结果 |
| --- | --- | --- |
| 紧凑与展开切换 | 用公开面板类型切换，保留选择；能恢复同一轮浏览位置 | ⬜ |
| 增量候选 | 追加候选不跳回顶部，能获知何时需要下一批；不依赖完整枚举 | ⬜ |
| 编号与身份 | 可见数字准确对应候选；**相同文字的不同候选可稳定区分** | ⬜ |
| 导航与鼠标 | 能实现本方案的高亮、收起及单击/双击语义；不抢宿主输入焦点 | ⬜ |
| 按键路由 | 外壳能先处理 Return、Escape、数字等；一次事件只产生一次动作 | ⬜ |
| 外观与可访问性 | 字体、明暗、长词阅读、键盘操作与辅助功能基本可用 | ⬜ |

实现注意（[功能方案 §7](docs/native-candidate-interaction.md#7-窗口实现先用公开组件验证必要时只换视图)）：`candidateSelectionChanged` 只用于高亮，`candidateSelected` 才进入确认链路；必须有组件候选标识到 Rime 全局索引的**明确映射**，不能把网格行号当候选索引，映射不可靠就不用该组件；仅设"不自动关闭窗口"不能替代按键拦截。

**交付物**：⬜ 每项成功/失败的记录 + 明确结论（IMKCandidates 可用 / 不可用）

---

### [ ] T0.4 Touch Bar 真正接入　🔴 本机无硬件

**具体工作**：在宿主输入会话中验证系统候选条显示、点按、取消、恢复及与屏幕并用。走系统文本输入机制（`NSCandidateListTouchBarItem` / `allowsTextInputContextCandidates`），路径见[功能方案 §7.1](docs/native-candidate-interaction.md#71-touch-bar-的系统接入边界)。

**交付物**
- [ ] 真实**跨应用**显示和选择证据（记录系统版本、宿主应用及版本、系统触控栏模式）
- [ ] 在具备实体触控栏的 Mac 上完成点按、滑动、取消、跨应用验收

**硬性边界**：设置 App 中自制 `NSTouchBar` 的演示**不算通过**；模拟器只作开发辅助；不能因一个应用显示成功就推断所有应用可用。

**当前处置**：本机（Mac mini，无触控栏）只能完成不依赖硬件的部分——桥接 API 的选型与静态核对、屏幕窗口与触控栏共用候选代次的接口设计。**硬件验证保留为未完成条件**，M0 不因其余任务通过而宣告完成（[实施计划 §5](docs/implementation-plan.md#5-第一批任务先回答决定架构的几个问题)）。

---

### [ ] T0.5 锁定实现

**具体工作**：公共屏幕组件不足时，验证最小 **AppKit 非激活 NSPanel + NSScrollView + 候选内容视图**，同时保留已通过的 Touch Bar 路径。

**交付物**
- [ ] 只选定**一种**屏幕实现；删除未采用的产品运行分支
- [ ] 更新 M1–M4 的任务估算
- [ ] 若 Touch Bar 跨应用链路未通过：记录确切失效场景、可行路径及对需求的影响，据此调整计划

**禁止**：不以改画一个自定义触控条代替 Touch Bar 验证；不盲目增加私有接口、全局触控栏接管或常驻服务（D-10）。

---

### M0 汇总结论（待填）

- [ ] 窗口路径结论：IMKCandidates / AppKit 滚动窗口
- [ ] Touch Bar 跨应用结论：通过 / 失败（含系统版本与宿主场景）
- [ ] 最低 macOS 版本实测记录
- [ ] 性能基线：同一测试序列下的 Rime 处理、窗口刷新、滚动耗时（记录默认含事件类别与耗时，**不含实际输入正文或个人词条**）
- [ ] 据此重估 M1–M5

## 3. 长按 Caps Lock 探索（独立于 M0，不阻塞首版）

[实施计划 §1](docs/implementation-plan.md#1-实施路线与首版完成标准)将其列为「首版核心体验稳定
之后独立验证」的可选增强；[decisions.md 3](docs/decisions.md#3-架构职责边界)记录了待验证的
具体问题。本节记录探索进展。

### 3.0 🔴 本机测不准：输入全部来自通用控制

2026-09-24 查明：**这台 Mac mini 没有直连键盘**（IOKit 查询键盘数为 0），
键鼠经**通用控制**来自 `Jamie's MacBook Pro`——也就是装着鼠须管、放着
`~/Library/Rime` 的那台机器。

这直接决定了本项探索在哪测：

| | 结论有效性 |
| --- | --- |
| 在 mini 上经通用控制测 | 只反映**远程输入这条路径**。远程输入可能不转发 Caps Lock 这类本地翻转键，只传最终修饰键状态 |
| 在 MacBook Pro 上用本地键盘测 | ✅ 这才是产品实际会遇到的配置 |

**依据**：参考实现在处理修饰键时专门写了 `inferModifierKeycode`，注释是
"Some remote desktop tools send flagsChanged with keyCode 0"——上游作者知道
远程输入的事件形态与本地不同，这正是同一类问题。

**探针已加入自动判别**：检测到通用控制运行时会打出警告，说明结论不可外推。

**同时确认**：D-03 的基线包就在 `Jamie's MacBook Pro` 上（§1.1 的取证目标）。

### 3.1 探针：`Glint --probe-capslock [秒数]`

```sh
./build/Glint.app/Contents/MacOS/Glint --probe-capslock 20
```

会弹一个窗口，请你**先短按一次 Caps Lock、再长按一次（约 1 秒）**。
探针只记录事件、判定长按是否可测，不改动任何设置。

**要回答的核心问题**：Caps Lock 是翻转键，按下时状态翻转、松开时状态不变。
若系统只在状态翻转时发 `flagsChanged`，那么「快按快放」与「按住一秒」看到的
事件序列**完全相同**——长按无从测量。反之则可行。

**它如何避免误导**：同时记录**所有**修饰键变化。按一下 Shift 即可确认采集通道是通的；
若连 Shift 都没出现，报告会明确说「这是通道问题，本次结果无效」，
而不是把「没收到事件」当成「长按不可行」。

### 3.2 已核实的访问权限（2026-09-24 实测）

| 能力 | 结果 | 含义 |
| --- | --- | --- |
| `CGEventSource.flagsState(.combinedSessionState)` | ✅ 免权限可用 | 能读到**会话级**真实 Caps Lock 状态。参考实现在激活时用它修正过期状态，值得沿用 |
| `CGEventTap`（全局物理按下/松开） | ❌ 需辅助功能授权 | 本进程未授权。这条路要求用户为输入法开启辅助功能 |
| `CGPreflightListenEventAccess` | ❌ 未授权 | 输入监控未开启 |
| `NSEvent` 本地监听 | ✅ 窗口获得焦点时可用 | 探针用的就是它；已确认窗口能拿到焦点 |

**初步结论（待实机数据）**：全局键盘监听不是可以「顺手用上」的路径，它要求用户
为输入法授予辅助功能/输入监控权限。decisions.md 记的「尚未决定引入全局键盘监听」
因此是个**需要用户决策**的问题，不是纯技术选型。

### 3.3 实测经过与转折（2026-09-24/25）

探针迭代了三轮才让采集通道可信，过程本身值得记录——**前两次的「0 事件」都是工具缺陷，不是结论**：

| 轮次 | 现象 | 真实原因 |
| --- | --- | --- |
| 1 | 窗口有焦点但 0 事件 | `addLocalMonitorForEvents` 返回的令牌被 `_ =` 丢弃，ARC 回收 → 监视器失效 |
| 2 | 自检通过、真实按键仍 0 事件 | 窗口没有文本输入上下文；已加入可编辑输入框 |
| 3 | 在 mini 与 MBP 上均为 0 事件 | **尚未定论**，见下 |

**已确认的事实**：在本机的自动化运行中，**`keyDown` 确实能到达普通应用**
（记录了 keyCode 7 / 34 / 0 / 45 等一系列普通按键）。因此「输入法吃掉了所有键盘事件」
这一假设**不成立**。

**探针的分层设计**（鼠标 → 键盘 → Caps Lock）用于逐层排除：某层到、下层不到，
问题就定位在该层。三次 0 事件更可能与「按键时探针窗口是否真的在前台」有关——
用户的操作焦点在终端与弹窗之间切换，而这一点无法由探针自行判定。

**转折：探针测错了路径。** 探针是普通应用，走 NSEvent 监听；而 Glint 是**输入法**，
走 IMK 路由（`recognizedEvents` 声明 `.flagsChanged`）。要得到产品会实际遇到的
结论，必须在输入法自身的上下文里测，而不是用普通应用外推。

**已在 Glint 里埋点**：`GlintInputController` 声明了 `.keyDown | .flagsChanged`
并记录每次修饰键事件的 keyCode、Caps Lock 状态、会话级状态与时间差 Δ。
**注销重新登录后的第一次输入就会产出决定性数据**——若一次 Caps Lock 按键只产生
一条「状态翻转」记录、没有紧随其后的第二条，则松开无独立事件，长按无从测量。

该埋点是临时的：它会在每次按 Shift 等修饰键时都写一条日志，结论拿到后应删除。

### 3.4 与 macOS 自带用法的关系

我们在 `Info.plist` 里设了 `TICapsLockLanguageSwitchCapable = true`，
即**短按 Caps Lock 切换输入源由系统负责**。这与长按是同一枚键上的两种手势，
长短按如何共存是本项探索的核心风险，也是 [decisions.md 3](docs/decisions.md#3-架构职责边界)
所列「待设计事项」的第一条。**在拿到探针数据之前，不预设方案。**

## 4. M1–M5 概要

细节与验收见[实施计划 §4](docs/implementation-plan.md#4-阶段依赖与退出条件) 与[§6](docs/implementation-plan.md#6-设置与词库任务的落地范围)。**依赖为串行**：M0 → M1 → M2 → M3 → M4 → M5。

| 阶段 | 内容 | 可交付 | 粗估 | 状态 |
| --- | --- | --- | --- | --- |
| M1 | 日常输入底座：全拼资源、输入与切换、隔离数据、输入源图标与 app 图标、开发构建及试用安装 | 开发测试包 | 3–5 日 | ⬜ |
| M2 | 完整候选体验：屏幕卷轴、Touch Bar、布局、高亮与过期事件处理 | 输入体验试用版 | 5–8 日 | ⬜ |
| M3 | 可视化设置：输入、外观、状态与高级入口；预览与实际生效反馈 | — | 3–5 日 | ⬜ |
| M4 | 词库、同步与迁移：个人快照、文本交换、专业词库、鼠须管迁移；iCloud 词典同步 → 配置同步 | 功能完整试用版 | 7–12 日 | ⬜ |
| M5 | 长期试用与交付准备：跨应用修复、性能记录、安装卸载与升级演练、开源材料 | 首版交付候选 | 3–5 日 + 7–14 天观察 | ⬜ |

合计约 **23–39 个有效开发日**。

**M4 内部顺序不可并行**：词典同步只需 M1 的数据隔离；配置同步还要等 M3 验证过的部署、生效确认与失败回滚机制。配置同步须维护哈希基线做三态判定（仅本地改／仅远端改／两侧都改），冲突不自动覆盖。

**跨阶段约束**
- 每阶段完成有意义的检查再进入下一阶段，避免最后才发现数据和事件模型不成立。
- UI 不得直接插入候选文字绕过组句与学习；同名选项不得维护两套持久化状态。
- 构建不隐式安装；安装不覆盖鼠须管；卸载程序与删除个人数据分开处理。
- 本轮**不创建远端仓库、不推送、不安装输入法**（[实施计划 §8](docs/implementation-plan.md#8-交付与开源准备)）。

## 5. 变更记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| 0.1 | 2026-09-24 | 建立任务清单：完成环境前置核对（发现本机无触控栏、无鼠须管与 `~/Library/Rime` 基线），把 M0 拆为 T0.1–T0.5 可勾选任务并记录交付物与阻塞，M1–M5 记为概要。仓库已初始化，尚无代码。 |
| 0.2 | 2026-09-24 | 工程骨架、librime 接入、候选协议与真实按键路径完成（离线用例 28/28）；首次安装并记录「需注销重新登录」；新增 §3 长按 Caps Lock 探针与已核实的访问权限。 |
