# 流光 / Glint

流光是面向 Apple Silicon Mac 的简体中文输入法，使用 [Rime/librime](https://github.com/rime/librime) 处理拼音、候选和学习。屏幕提供卷轴候选；配有 Touch Bar 的 Mac 可显示同一轮中文候选和手动下一词联想。英文继续使用 macOS 的 ABC 输入源。

当前版本 **0.1.0**。正式项目交付物是 `dist/Glint-0.1.0-arm64.dmg`，`build/Glint.app` 仅为构建中间件。Apple Developer ID 与公证按本次交付约定暂缓；这份 Apple Development 签名包不能宣称已通过 Gatekeeper 站外分发认证。最低 macOS 13.0 只是编译目标，尚未跨版本验收。

## 安装与使用

先完成正在输入的文字，再打开 DMG 中的「安装流光.app」并点击安装。更新时安装器会暂时切换为英文，正常退出旧版后再替换程序。首次安装可点击「打开键盘设置」，在「文本输入 → 编辑…」中添加「流光」；已经添加过的用户，完成后从菜单栏选择「流光」即可。安装保留 `~/Library/Glint` 中的设置、词库和已下载方案。安装、升级与卸载现状见[交付与运维](docs/release.md)。

在输入法菜单打开「流光设置…」：

- **输入方案**：内置雾凇全拼及七种双拼；万象 Base 按需从官方源下载，含简体模型约 455 MB，安装后可本地切换。方案和键位不从 `~/Library/Rime` 读取。
- **候选外观**：字体、12–36 pt 字号、系统／浅色／深色与单行／展开预览。
- **词库与学习**：个人快照与文本导入导出、雾凇专业词库、从鼠须管目录选择性迁移。
- **iCloud 同步**：默认关闭，只处理个人学习数据及可选用户补丁，不同步成品方案和模型；两台 Mac 的传播与收敛按本次要求未验收。
- **关于与诊断**：查看版本、数据目录和限量文件日志。

Touch Bar 联想仅接受手动触摸，键盘不选联想词；没有 Touch Bar 时跳过联想，普通中文输入仍可用。按键、候选和上屏规则见[输入行为](docs/input-behavior.md)。

## 从源码构建

需要 Xcode、`make` 和项目约定的 Apple Development 签名证书。构建不会自动安装或修改日用词库。

```sh
make deps          # 获取固定版本的 librime
make bundle-rime   # 准备内置方案资源
make               # 生成 dist/Glint-0.1.0-arm64.dmg 和 SHA256SUMS
```

源码按职责放在 `sources/App`、`Input`、`Engine`、`Candidates`、`Schemes`、`Data`、`Sync`、`Settings`；C 桥接位于 `sources/rime`。安装器在 `installer/`，构建脚本在 `scripts/`。历史诊断探针和 `make check` 已从发布仓库移除；本次没有新增测试代码。

## 维护文档

每份文档对应一个长期用途：

| 文档 | 保留理由 |
| --- | --- |
| [架构与目录](docs/architecture.md) | 定位代码、运行时及跨模块修改边界。 |
| [输入行为](docs/input-behavior.md) | 明确键盘、屏幕候选与 Touch Bar 的产品规则。 |
| [用户数据与同步](docs/data-and-sync.md) | 保护学习库、配置和同步事务的完整性。 |
| [交付与运维](docs/release.md) | 复现 DMG、安装、诊断并理解尚未完成的验收。 |
| [排障与踩坑](docs/troubleshooting.md) | 保留已查明的根因、判据和修复原则，避免重复调查。 |
| [第三方与许可证](THIRD_PARTY.md) | 追溯随包组件、来源、版权与授权条件。 |

项目采用 [GPLv3](LICENSE)。个人数据不进入仓库或源码归档。
