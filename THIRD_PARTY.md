# 第三方组件与许可证

本项目按 GPLv3 发布（见 [LICENSE](LICENSE)）。下面的组件被**打进 Glint.app**，
因此必须随分发保留各自的版权声明与许可证正文——这不是可选项，是 BSD-3-Clause
和 GPLv3 各自的条款要求。

许可证正文存放在 [licenses/](licenses/)，并随应用打包到
`Glint.app/Contents/Resources/licenses/`。

0.1.0 DMG 的源码归档除本项目源码外，还收录 `third-party/` 下固定版本的
librime、三个插件、LibYAML 源码包及预测模型原始文本；打包时逐一核对 SHA-256。
内置雾凇方案的 YAML、Lua 与词库原始文件位于输入法载荷的 `rime.tar.gz`，
其清单与许可证随包保存。万象按需下载，来源与许可见下文。

## 随产物分发的组件

版本由 `scripts/fetch-librime.sh` 固定，取自 librime 1.17.0 的官方 release
（对应提交 `33e7814`）。
release 包内的 `version-info.txt` 记录了各插件的提交号，下表与其一致。

| 组件 | 提交 | 许可证 | 正文 |
| --- | --- | --- | --- |
| [librime](https://github.com/rime/librime) 1.17.0 | `33e7814` | BSD-3-Clause | [librime-BSD-3-Clause.txt](licenses/librime-BSD-3-Clause.txt) |
| [librime-lua](https://github.com/hchunhui/librime-lua) | `ec52e48` | BSD-3-Clause | [librime-lua-BSD-3-Clause.txt](licenses/librime-lua-BSD-3-Clause.txt) |
| [librime-octagram](https://github.com/lotem/librime-octagram) | `dfcc151` | **GPL-3.0** | [librime-octagram-GPL-3.0.txt](licenses/librime-octagram-GPL-3.0.txt) |
| [librime-predict](https://github.com/rime/librime-predict) | `920bd41` | BSD-3-Clause | [librime-predict-BSD-3-Clause.txt](licenses/librime-predict-BSD-3-Clause.txt) |
| [LibYAML](https://pyyaml.org/wiki/LibYAML) 0.2.5 | 固定源码包 SHA-256，见 `scripts/fetch-libyaml.sh` | MIT | [libyaml.txt](licenses/libyaml.txt) |
| [rime-ice（雾凇拼音）](https://github.com/iDvel/rime-ice) | 本地基线资源，见下方记录 | GPL-3.0-only | [rime-ice-GPL-3.0.txt](licenses/rime-ice-GPL-3.0.txt) |

LibYAML 静态链接，仅解析方案配置；增加原因是 Rime C API 的路径读取无法完整访问包含 `/` 的字面补丁键。

雾凇随包提供全拼、7 种双拼及共用词库、Lua、OpenCC 资源。当前基线归档 SHA-256 为 `790c84c885e8170ca3424dac6645b5cc64ca7f06d2b55aa1f8449e58a7b0b329`，逐文件清单随资源保存为 `data-manifest.sha256`。App 内资源采用 `rime.tar.gz` 压缩存放，包外同时附带该清单的 `rime-manifest.sha256` 副本供初始化检查；压缩不改变原资源及许可证。基线的上游提交尚未确认，不将另一个参考检出的提交冒充基线版本。资源中的作者声明保留；Glint 另生成 `default.custom.yaml`，默认雾凇全拼并关闭 Shift 切英文。构建来源和筛选规则见 `scripts/bundle-rime-data.sh`。

### 上屏后联想数据

`glint-predict.db` 基于 Rime 官方 [librime-predict data-1.0](https://github.com/rime/librime-predict/releases/tag/data-1.0) 的 `predict.txt`，源文件 SHA-256 为 `df0f7a9ef96569da402d9ea2376aefad4d15382ebcccb05ec84a0acbc00c7f83`。该发布说明数据由 essay + octagram 生成；保留 [rime-essay 的 LGPLv3 正文](licenses/rime-essay-LGPL-3.0.txt)、已有 octagram GPLv3 和 predict BSD-3-Clause 声明。

Glint 在构建时用 macOS 的繁简转换处理查询词和候选，合并转换后的重名项及权重，再用官方 `build_predict` 编码；没有把繁体模型直接用于简体匹配。生成脚本为 `scripts/build-prediction-data.sh`、`scripts/simplify-prediction.swift`，上游工具与头文件下载固定提交和 SHA-256。随应用增加约 7.5 MB 模型；构建用的 Boost、Marisa 和 Rime 源码头文件不随应用打包，DMG 的源码归档提供对应来源及预测原始文本。

## 按需下载的方案

万象资源不随 Glint.app 分发。首次使用从官方发布源下载，固定大小和 SHA-256 校验，保存来源清单及许可证到本地方案目录：

| 资源 | 官方来源 | 许可 |
| --- | --- | --- |
| 万象 Base 18.0.11 | [amzxyz/rime-wanxiang](https://github.com/amzxyz/rime-wanxiang/releases/tag/v18.0.11) | 该版本 LICENSE 正文为 CC BY 4.0 |
| 万象 LTS 简体模型 | [amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG/releases/tag/LTS) | LTS LICENSE 正文为 CC BY 4.0 |

Base zip 不含许可证，安装器另从官方版本下载两份许可证并校验。Glint 只生成用户补丁以配置输入方式，不改方案源码；下载清单、作者和校验值见 `sources/Schemes/GlintInputScheme.swift`。模型的 LTS 地址可被上游更新；校验不符会拒绝安装，需要更新已验证的资源清单。

> **关于 librime-octagram 的许可证**：GitHub 的 license API 把四个仓库一律报成
> `BSD-3-Clause`，但 librime-octagram 的 `LICENSE` 文件正文是 **GPLv3 全文**。
> 本表按**文件正文**记录，不采信分类器结果。GPLv3 与本项目的 GPLv3 方向兼容，
> 但记录必须与实际一致。

## 复用的源码

本项目复用并修改了鼠须管的键码映射文件；保留原版权、GPLv3、提交号与修改说明。

### 已复用

| 本仓库文件 | 来源文件 | 提交 | 修改说明 |
| --- | --- | --- | --- |
| `sources/Input/MacOSKeyCodes.swift` | [squirrel/sources/MacOSKeyCodes.swift](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/MacOSKeyCodes.swift) | `0cd71a61` | 见下 |

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

## 更新方式

改动依赖版本时（`scripts/fetch-librime.sh` 中的 `RIME_VERSION` / `SHA256`），
必须同步更新本表与 `licenses/` 下的正文，否则登记即失效。
