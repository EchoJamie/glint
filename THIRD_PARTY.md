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

## 参考但未分发的代码

以下仅作为**实现参考**阅读，目前没有任何代码被复制进本仓库。实际复用后须在此
补充来源文件、提交号与修改说明（[decisions.md 5.2](docs/decisions.md#52-已核对的许可方向)）。

| 来源 | 提交 | 许可证 | 用途 |
| --- | --- | --- | --- |
| [rime/squirrel](https://github.com/rime/squirrel) | `0cd71a61` | GPLv3 | 系统接入、候选窗口、配置读取的复用候选（计划 §3 列了具体文件） |

## 尚未纳入

- **rime-ice（雾凇拼音）**：目前只用于**测试数据**，不进产物。GPL-3.0-only。
  若日后随产物分发方案或词库，须按实际分发内容履行其许可并在此登记。
- **Sparkle**：本轮不引入（[实施计划 §3](docs/implementation-plan.md#3-参考实现如何取舍)）。

## 更新方式

改动依赖版本时（`scripts/fetch-librime.sh` 中的 `RIME_VERSION` / `SHA256`），
必须同步更新本表与 `licenses/` 下的正文，否则登记即失效。
