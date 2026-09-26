# 用户数据与同步

本文记录用户数据的归属和完整性边界。涉及词库、方案切换或同步的改动必须先核对这些路径；不能用真实个人数据作故障样本。

## 本机目录

| 路径 | 内容与规则 |
| --- | --- |
| `~/Library/Glint` | 雾凇方案的 Rime 工作目录、个人学习库及全局外壳设置。与 `~/Library/Rime` 完全分离。 |
| `~/Library/Glint/schemes/wanxiang` | 按需下载的万象方案、模型、配置及其独立学习库。 |
| `~/Library/Glint/glint-settings.json` | 候选外观、当前方案、同步偏好；修改已管理字段时保留未知字段。无效 JSON 不覆盖。 |
| `.glint-maintenance/<UUID>/` | 维护副本、原文件 `before/` 备份与中断恢复 journal。 |
| `.glint-downloads/<UUID>/` | 尚未完成的方案下载；失败或取消只清理本次临时文件。 |
| `~/Library/Glint/logs/` | 限量诊断日志，见[交付与运维](release.md)。 |

成品方案、公开词库、Lua、模型和编译结果只在本机安装，不通过 iCloud 同步。全拼与双拼共享同一方案的学习库；雾凇和万象不互相转换编码或混合学习权重。键位选择每台设备独立，从 Rime 编译后的配置读回，不另存一份状态。

## 词库与迁移

个人学习库由 Rime 管理。原生 `.userdb.txt` 快照包含词典、设备身份、学习时钟及 `c/d/t` 值；普通 TSV 文本用于词语与编码交换，不代表完整学习历史。导入前检查 UTF-8、每行结构、身份、条目数与完整尾行；Rime 会忽略部分坏行，不能只凭其返回成功就认定全部导入。

鼠须管迁移不在活动的 `~/Library/Rime` 里初始化 Glint 引擎。活动 `.userdb` 需要同协议锁定复制并逐文件比较前后 SHA-256；源正在写入或内容变化时拒绝。仅在独立副本中运行 Rime 备份，再合并到 Glint 的事务副本。默认保留原 Glint 学习记录，原鼠须管目录只读。专业词库入口只管理雾凇主词典的已标记依赖行，停用专业词库不删除个人学习库。

## iCloud 协议与边界

同步默认关闭，使用 iCloud Drive 普通文件，根目录为 `~/Library/Mobile Documents/com~apple~CloudDocs/Glint`。当前只调度正在使用的方案；万象个人数据在云端 `schemes/wanxiang` 命名空间。**两台 Mac 的传播、收敛和离线恢复按本次要求未验收**，不能把单机隔离回归或文件日志表述成这些结果。

个人词典的发布单元为 `snapshots/<installation_id>/<dictionary>.json`，单文件同时保存 Rime 原生快照、身份、条目数和 SHA-256。同步前拒绝未下载完的 `.icloud` 占位、未解决的文件版本冲突、符号链接及内容不完整的快照。`installation.yaml`、`user.yaml`、活动 `.userdb`、`build/`、本地 `sync/`、方案包和模型均不上传。

配置只共享允许名单中的 `.custom.yaml` 的 `patch` 内容，并排除设备本地的 `schema_list`、`speller/algebra`、`glint` 及其子路径。云端 `configuration/<文件名>/<UUID>.json` 是不可变版本，记录内容哈希与父版本；本机 `glint-sync-state.json` 保存基线，`glint-sync-conflicts.json` 保存待处理冲突。两侧修改或存在多个云端顶点时由用户选择；删除必须是明确版本，云目录缺失不能解释为删除本机文件。

冲突确认必须携带用户看到的本机哈希和云端版本；维护开始前及提升正式目录前重新比对。云端发布失败时不提升本机词库、配置或基线。配置变化要在隔离副本重新部署；同步中仍沿用维护队列，组合未结束时等待。不要为了简化代码而去掉这些完整性条件。
