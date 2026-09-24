# 任务清单

- 日期：2026-09-24
- 状态：**M0 进行中。代码侧基本就绪，卡在输入源注册**（见 §0）。
  librime 1.17.0 已接入并嵌入产物；候选协议与真实按键路径通过 **28/28** 离线用例；
  输入控制器已接引擎（预编辑 + 提交）。但**从未在真实输入会话里跑过**——
  一次都没有。候选窗口与 Touch Bar 未开始。
- 最近一次更新：2026-09-25。文档条理按「当前状态在前、排查经过在后」重排。

- 权威来源：[实施计划](docs/implementation-plan.md)（阶段、依赖、范围、验收、估算）、[功能方案](docs/native-candidate-interaction.md)（候选与 Touch Bar 交互契约）。
- 本文件是**执行视图**：把阶段拆成可勾选的任务，记录状态、交付物与实际证据。
- 勾选规则：只勾选**有证据**的任务。写入文件、构建"能编译"、在一台设备上显示成功，都不等于对应验收项已通过（[实施计划 §7](docs/implementation-plan.md#7-验证与试用安排)）。

## 0. 当前阻塞：输入源注册不生效

**一句话**：TCC 输入监控权限已通（已验证），但注册仍不落成输入源，
系统**从未尝试加载我们的 bundle**。下一步是「TCC 通过的注册 + 注销重登」这个
尚未试过的组合。

### 0.1 已确证的事实

| 事实 | 证据 |
| --- | --- |
| `TISRegisterInputSource` 内部**同步**查「输入监控」权限 | 同一进程内的 TCC 往返日志 |
| TCC 判**归责对象**，不是发起进程 | 从 Ghostty 跑 → `auth_value=0`；从 Terminal 跑 → `auth_value=2` |
| 从 **Terminal.app** 跑，权限检查**已通过** | `03:44:05 auth_value=2 result=true` |
| 通过后系统**有反应**：`TextInputMenuAgent` 被唤醒并重载偏好 | 同一时刻的日志 |
| 但**系统从未尝试加载** `/Library|~/Library/Input Methods/Glint.app` | 全时段日志无相关记录 |
| 本机**无任何第三方 IME** 可作对照 | TIS 的 11 个 `InputMethodModeEnabled` 全是苹果自家 |

### 0.2 已排除（全部实测，不是推理）

安装位置（用户级/系统级）· 注册身份（登录用户/root）· LaunchServices 登记 ·
`Info.plist` 键集（**最小包实验**同样不注册，见 `scripts/bisect-bundle.sh`）·
签名（补齐 entitlements + Hardened Runtime 后仍如此）· 偏好注入
（写进 `AppleEnabledInputSources` 也不进 TIS 列表——TIS 的清单不从那份偏好建）·
注销（在 TCC 失败的状态下试过一次，无效，但那次的注册根本没被受理）。

### 0.3 尚未试过的组合

**TCC 通过的注册 + 注销重登。**

之前那次注销是在 TCC 一直失败时做的，注册根本没被受理，注销自然无用。
现在从 Terminal 跑已经能通过权限检查，这个组合值得走一遍：

```sh
# ① 在 Terminal.app 里（不是 Ghostty）
"$HOME/Library/Input Methods/Glint.app/Contents/MacOS/Glint" --install

# ② 自己确认这次 TCC 是通过的（要看到 auth_value => 2）
/usr/bin/log show --last 1m --style compact --info --debug \
  --predicate 'process == "Glint"' | grep -A4 ListenEvent | grep auth_value

# ③ 注销、重新登录

# ④ 回来查
"$HOME/Library/Input Methods/Glint.app/Contents/MacOS/Glint" --list-input-sources glint
```

诊断脚本：`scripts/diagnose-registration.sh`（会识别当前终端并列出相关授权）。

### 0.4 若上述仍失败：最后一个有分量的假设

**macOS 26/27 对未公证输入法施加了更强限制。**
依据：[WindInput](https://github.com/huanfeng/WindInput) 的 macOS 构建文档明写
「macOS 26 (Tahoe) 对未公证输入法限制更强」。

而本项目按 [D-15](docs/decisions.md#2-已确定的方向) 使用**免费 Apple Development
证书**，**技术上无法公证**。若这条成立，问题就不是「怎么调」而是
「这条路在这台机器上是否成立」——**会影响 D-14（平台范围）与 D-15（证书）**，
需要用户决策，不是技术选型。

### 0.5 两条待确认的决策偏离

均由本次排查产生，**已实施但未获用户确认**：

1. **`InputMethodConnectionName` 改名**（[decisions.md 5.4](docs/decisions.md#54-项目标识版权与签名) 原定 `Glint_Connection`）
   → 改为 `com.github.echojamie.glint_Connection`。
   依据：vChewing 维护者的 2026 IMK 指南指出该键**只能是
   `<bundle identifier>_Connection`**（macOS 10.7 起的 NSConnection 约定），
   不合规会导致输入法加载失败。原值是照抄鼠须管的，而鼠须管同样不合规——
   它没开沙盒所以享有系统宽容。
2. **`AppleEnabledInputSources` 被注入两条**（未起作用）
   → 保留还是还原由用户定：
   `python3 scripts/register-input-source-workaround.py --revert`

### 0.6 可以在 MacBook Pro 上做的事

用户已决定改在 MBP（装有鼠须管、接实体键盘、非通用控制注入）上处理。
那边有两件事：

**① 验证注册（可能根本不需要费这些周折）**
MBP 上鼠须管能正常工作，说明它的 macOS 版本没有 macOS 26/27 的那些限制。
把仓库拷过去直接 `make build && make install && --install` 试，可能一次就成。

**② 导出现有的 Rime 基线（D-03，长期挂着的一项）**

```sh
cd ~/Library/Rime
tar --exclude=build --exclude='*.userdb' -czf ~/Desktop/rime-baseline.tar.gz .
```

排除 `build/` 与 `*.userdb/`，只取方案与配置（几百 KB）。**个人学习词条不进这个包**，
那是 M4 的事。拿到后可以：
- 反查实际使用的 rime-ice 版本（本机克隆的是今天 main，不是用户在用的那份）
- 取得用户改过的 `*.custom.yaml`

这一步做完，「固定体验基线」才可能勾选（[§1.1](#11-参考仓库与方案数据2026-09-24-已就位)）。

### 0.7 完整排查经过（时间倒序，保留供追溯）

1. **最初**：`make install` + `--install` → `TISRegisterInputSource` 返回
   `noErr`，但 TIS 331 个输入源中无 glint。重启三个代理、`launchctl kickstart`
   （被 SIP 拦）、`open` 拉起 app，均无效。
2. **怀疑位置**：查参考实现，发现鼠须管装的是系统级 `/Library/Input Methods/`
   （`DSTROOT`），而本项目按 5.4 装用户级。改用系统级 → 仍不生效。
   期间发现并修掉一个真 bug：`--install` 注册的是**写死的**用户级路径，
   从系统级副本运行也注册用户级那份（见提交 46518d5）。
3. **怀疑身份**：对比 root 与登录用户注册（鼠须管 postinstall 是 root 注册、
   降权启用）→ 两者都失败。
4. **怀疑 plist**：解包鼠须管 1.1.2 的 `.pkg`，逐键比对 `ComponentInputModeDict`
   → 结构完全一致。
5. **怀疑签名**：补 `entitlements`（`disable-library-validation` +
   `app-sandbox=false`）并开 Hardened Runtime（此前两者皆无，
   而 `disable-library-validation` 本来就是加载 adhoc 签名的 librime 所必需）
   → librime 仍正常，注册仍失败。
6. **找到 TCC**：日志显示 `TISRegisterInputSource` 同步查
   `kTCCServiceListenEvent`，且归责给 `responsible process`。
7. **一度误判**：用户给 Glint 授权后检查仍失败，我据此写下「TCC 是真实的门但
   不是完整原因」——**这个修正是错的**。真实原因是**我又重新签名了**
   （改连接名），TCC 授权绑定 CDHash，旧的授权随之作废。
8. **用户质疑「鼠须管装的时候也没注销」**，推动查参考实现与网上资料，
   否掉了「需要注销是固定行为」这个抄来的结论。
9. **改用查证**：搜索确认 macOS 26/27 上第三方输入法自动注册存在失效
   （WeType 有逐条吻合的先例），社区办法是手工注入 `AppleEnabledInputSources`
   ——**实测对我们无效**，TIS 的清单不从那份偏好建。
10. **对照实验**：`scripts/bisect-bundle.sh` 最小包也不注册 → 不是 plist 键集问题。
11. **闭环**：从 Terminal.app 跑，TCC 通过（`auth_value=2`），系统有反应
    （`TextInputMenuAgent` 唤醒）但仍不落成输入源，且系统从未尝试加载 bundle。

### 0.8 排查过程中踩到的坑（值得记住）

- **`log` 是 zsh 的内建命令**（列登录用户）。`log show ...` 不报错但什么都不执行，
  此前几次「日志查询无结果」全是假的。查系统日志要用 `/usr/bin/log`。
- **TCC 授权绑定代码签名（CDHash）**。授权后**不要再重新签名**——任何
  `make build` 都会作废授权。调试顺序必须是：先定稿签名、再授权、再验证。
- **TCC 判归责对象，不是发起进程**。从终端跑的注册，判的是那个终端有什么权限。
- **TCC 库只有 Ghostty 读得了**（它有完全磁盘访问）；Terminal.app 读不了。

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

> **⚠️ 开工前先看这条。** [IMK 开发指南（2026）§9](https://github.com/ShikiSuen/ShikiSuen/blob/df1c188261d25346ed51d18b5e7e5aed5962e2b8/TechNotes/macOS_Input_Method_Development_Guidelines_2026/macOS_Input_Method_Development_Guidelines_2026-ENU.md)
> 标题就是**「避免使用 IMKCandidates」**，称其为「陈年垃圾」，并指出
> **macOS 26 内置的日文输入法就是它的受害者**——玻璃背景全透明、露出白底，
> 候选文字也是白的，几乎看不清。这是 Apple 自己在 LiquidGlass 上的适配失当。
>
> **所以 T0.3 的验收条件要增加一项：macOS 27 上的渲染质量。**
> 这一项预期大概率不过，届时直接走 T0.5 的 AppKit 方案，不算意外。
> 但**仍要实测**——我们需要自己的证据，不能拿别人的结论当验收。
>
> 另：§8 指出 **macOS 26 起 NSWindow 占用的内存永不回收**，候选窗口数量要克制。
> `Info.plist` 加 `UIDesignRequiresCompatibility` 可降到 macOS 15 水平，属临时手段。

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

### 3.4 IMK 开发指南（2026）里对本项目有直接影响的条目

来源：[macOS Input Method Development Guidelines for 2026](https://github.com/ShikiSuen/ShikiSuen/blob/df1c188261d25346ed51d18b5e7e5aed5962e2b8/TechNotes/macOS_Input_Method_Development_Guidelines_2026/macOS_Input_Method_Development_Guidelines_2026-ENU.md)
（vChewing 维护者，覆盖 macOS 10.9 – 26）。以下均已落到具体行动。

**已修：`InputMethodConnectionName` 值错了。** 该键**只能**是
`<bundle identifier>_Connection`（macOS 10.7 起的 NSConnection 约定），
不合规会导致输入法加载失败。我们原为 `Glint_Connection`（照抄鼠须管），
已改为 `com.github.echojamie.glint_Connection`。
`decisions.md` 5.4 里的值需要同步修订——**那是个需要你确认的偏离**。
源头是 Apple 自己的 NumberInput 示例给了坏榜样；鼠须管也用不合规的名字，
但它没开沙盒、享有系统宽容，我们不该依赖这个。

**未处理，但影响 T0.3：§9「避免使用 IMKCandidates」。**
指南称其为「陈年垃圾」，并指出 **macOS 26 内置日文输入法就是它的受害者**——
玻璃背景全透明、露出白底，候选文字也是白的，几乎看不清。这是苹果自己在
LiquidGlass 上的适配失当。
→ T0.3 原本要验证「IMKCandidates 能否承担屏幕窗口」，**现在多了一条要验的：
在 macOS 27 上的渲染质量**。若不过，直接走 T0.5 的 AppKit 方案。

**未处理，但影响候选窗口设计：§8「macOS 26 起 NSWindow 内存永不回收」。**
每个 NSWindow 的基线开销在 LiquidGlass 下被放大，且**系统不会回收**。
指南建议合并窗口、减少数量。`Info.plist` 里加 `UIDesignRequiresCompatibility`
可把内存降到 macOS 15 水平，但属临时手段，Apple 随时可撤。

**未处理，且我们已违反：§5「IMKInputController 不得持有任何对象」。**
IMK 在**每次切换输入法**时都会新建 controller 实例；状态应放在以 client 为键的
会话对象里，controller 只做转发。
我们目前是：静态共享一个 `RimeEngine` + 一个 session，控制器自己管
`hasSession`。**快速切换（CapsLock 连按）时新 controller 会 openSession
掉旧的**——这是真实缺陷，属 M1。

**记录但暂不采纳：§2「始终开启沙盒」。** 指南主张输入法必须开沙盒，视其为
安全底线。但这与本项目已确认的 **iCloud 同步需求冲突**——沙盒会挡住直接
读写 `~/Library/Mobile Documents`（decisions.md 3.2 的技术前提）。
这是一条需要用户决策的取舍，不是纯技术选型。

### 3.5 与 macOS 自带用法的关系

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
| 0.2 | 2026-09-24 | 工程骨架、librime 接入、候选协议与真实按键路径完成（离线用例 28/28）；首次安装；新增 §3 长按 Caps Lock 探针与已核实的访问权限。 |
| 0.3 | 2026-09-25 | §0 按「当前状态在前、排查经过在后」重排：确证 TCC 归责链、列清已排除项与未试组合、记录两条待确认的决策偏离；新增 §0.6「在 MBP 上要做的事」；T0.3 补入 IMKCandidates 的实测预警。 |
