# 第三方组件与许可证

本项目按 GPLv3 发布（见 [LICENSE](LICENSE)）。下面的组件被**打进 Glint.app**，
因此必须随分发保留各自的版权声明与许可证正文——这不是可选项，是 BSD-3-Clause
和 GPLv3 各自的条款要求。

许可证正文存放在 [licenses/](licenses/)，并随应用打包到
`Glint.app/Contents/Resources/licenses/`。

## 随产物分发的组件

版本由 `scripts/fetch-librime.sh` 固定，取自 librime 1.17.0 的官方 release
（对应提交 `33e7814`，见 [decisions.md D-02](docs/decisions.md#2-已确定的方向)）。
release 包内的 `version-info.txt` 记录了各插件的提交号，下表与其一致。

| 组件 | 提交 | 许可证 | 正文 |
| --- | --- | --- | --- |
| [librime](https://github.com/rime/librime) 1.17.0 | `33e7814` | BSD-3-Clause | [librime-BSD-3-Clause.txt](licenses/librime-BSD-3-Clause.txt) |
| [librime-lua](https://github.com/hchunhui/librime-lua) | `ec52e48` | BSD-3-Clause | [librime-lua-BSD-3-Clause.txt](licenses/librime-lua-BSD-3-Clause.txt) |
| [librime-octagram](https://github.com/lotem/librime-octagram) | `dfcc151` | **GPL-3.0** | [librime-octagram-GPL-3.0.txt](licenses/librime-octagram-GPL-3.0.txt) |
| [librime-predict](https://github.com/rime/librime-predict) | `920bd41` | BSD-3-Clause | [librime-predict-BSD-3-Clause.txt](licenses/librime-predict-BSD-3-Clause.txt) |

> **关于 librime-octagram 的许可证**：GitHub 的 license API 把四个仓库一律报成
> `BSD-3-Clause`，但 librime-octagram 的 `LICENSE` 文件正文是 **GPLv3 全文**。
> 本表按**文件正文**记录，不采信分类器结果。GPLv3 与本项目的 GPLv3 方向兼容，
> 但记录必须与实际一致。

## 复用的源码

按 [decisions.md 5.2](docs/decisions.md#52-已核对的许可方向)，复用 GPLv3 的鼠须管
代码在本项目（同为 GPLv3）内合规，但**必须登记来源、提交号与修改内容**。

### 已复用

| 本仓库文件 | 来源文件 | 提交 | 修改说明 |
| --- | --- | --- | --- |
| `sources/MacOSKeyCodes.swift` | [squirrel/sources/MacOSKeyCodes.swift](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/MacOSKeyCodes.swift) | `0cd71a61` | 见下 |

**`MacOSKeyCodes.swift` 的修改**（文件末尾亦有同样记录）：

1. 类型与函数改名：`SquirrelKeycode` → `MacOSKeyCode`；`osxKeycodeToRime` →
   `rimeKeyCode(keycode:keychar:shift:caps:)`；`osxModifiersToRime` → `rimeModifiers(from:)`。
2. 修饰键掩码改为引用本仓库的 `RimeModifier`。参考实现经
   `Sources/Squirrel-Bridging-Header.h` 引入 librime 的 `rime/key_table.h`，
   而**该头文件不在官方预编译包内，且它 `#include <X11/keysym.h>`**，
   macOS 不自带 X11（需 XQuartz）。
3. `XK_*` 常量改为本仓库的 `XK` 枚举，取值按 X11 `keysymdef.h`（X Consortium）
   复述，与 librime 使用同一套定义。
4. 补入 `kVK_ANSI_KeypadEquals`（参考实现遗漏）。**映射关系本身未改动。**
5. 注释改为中文，补充取值来源说明。

`RimeModifier` 的掩码值已对照 librime `src/rime/key_table.h` 的 `RimeModifier` 逐项核过。

### 尚未复用（仍仅作参考阅读）

| 来源 | 提交 | 许可证 | 用途 |
| --- | --- | --- | --- |
| [rime/squirrel](https://github.com/rime/squirrel) | `0cd71a61` | GPLv3 | 系统接入（`SquirrelInputController.swift`）、候选窗口（`SquirrelPanel.swift` / `SquirrelView.swift`）、配置读取（`SquirrelConfig.swift`）。计划 §3 列了具体文件，逐项复用后须在上表登记。 |

## 尚未纳入

- **rime-ice（雾凇拼音）**：目前只用于**测试数据**，不进产物。GPL-3.0-only。
  若日后随产物分发方案或词库，须按实际分发内容履行其许可并在此登记。
- **Sparkle**：本轮不引入（[实施计划 §3](docs/implementation-plan.md#3-参考实现如何取舍)）。

## 更新方式

改动依赖版本时（`scripts/fetch-librime.sh` 中的 `RIME_VERSION` / `SHA256`），
必须同步更新本表与 `licenses/` 下的正文，否则登记即失效。
