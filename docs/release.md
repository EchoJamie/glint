# 构建、交付与运维

0.1.0 的交付物是 Apple Silicon DMG，`build/Glint.app` 只是中间件。仓库没有安装前自动写入日用词库或系统输入源的构建步骤。

## 构建与包内容

需要 Xcode、`make` 和约定的 `Apple Development: echojamieee@outlook.com (9JHY98AJMC)` 证书。

```sh
make deps          # 固定版本的 librime
make bundle-rime   # 准备内置雾凇资源
make               # dist/Glint-0.1.0-arm64.dmg + dist/SHA256SUMS
```

`make build` 只做内部 App；`make dmg` 显式重做交付盘。依赖及构建缓存位于忽略的 `deps/`、`build/`，交付物位于忽略的 `dist/`。打包脚本拒绝非约定签名。DMG 只含「安装流光.app」、安装说明和同版本源码归档；输入法 `.app` 作为签名安装器内的 ZIP 载荷，避免挂载时出现第二份同身份输入法。源码归档附本项目文件、许可证、固定摘要的第三方源码及预测数据原文；内置雾凇原始资源随输入法载荷提供。

资源和动态库必须先嵌入，最后才签 App；签名后改资源会破坏封存。交付时核对 `SHA256SUMS`、`hdiutil verify`、输入法／安装器／DMG 的签名、架构、版本和只读挂载内容。源码归档不能包含个人词库、原始日志、截图或构建缓存。

App 和嵌入的 librime／插件现在由同一团队证书签名。`disable-library-validation` 仍保留在 0.1.0 的已验收配置中；旧文档所称“动态库为 ad-hoc 签名、该豁免必需”已被签名结果推翻。移除豁免需要在真实输入宿主中验证插件加载与中文输入，不能仅凭签名静态检查放行。

## 安装、升级和卸载

在 DMG 中打开「安装流光.app」并点击安装。安装器解包并检查载荷签名，用无 `.app` 后缀的暂存件校验后替换到 `~/Library/Input Methods/Glint.app`。旧程序仅在安装目录的 `.glint-install-*` 暂存目录中保留至替换完成：替换失败则恢复，成功则随暂存目录删除；如果恢复本身失败，保留暂存目录并报告位置。用户数据不覆盖。首次使用在系统设置的输入法列表添加「流光」。登记成功不等于真实宿主已激活，必要时在 TextEdit 实际打字确认。

安装前完成正在输入的文字。原生安装器校验新包后，只对正式安装路径的旧版请求正常退出；若当前选中流光，先通过 TIS 切至系统英文键盘。确认旧版已退出后才替换程序，等待超过 5 秒或退出被拒绝则停止更新，不强制结束。输入法在词库／同步维护中拒绝正常退出，允许退出时交还组合并关闭 Rime。此保护只适用于包含该处理的版本；更早版本的退出行为需单独核对。

完成页根据流光输入源是否已启用，分别提供首次添加的「打开键盘设置」按钮或从菜单栏选择流光的提示；「完成」按钮退出安装器。正常更新不要求用户管理进程或重新登录。`make install` 与 `make uninstall` 是开发入口，前者只替换文件，不执行原生安装器的退出流程；后者只移除程序，没有完整的面向用户卸载流程，且不删除 `~/Library/Glint`。旧版回退若涉及数据格式变更，不能只替换程序。运行中升级／回退和完整卸载仍需单独验收。

本版按约定使用 Apple Development 证书；Developer ID 认证与公证不在本次范围。签名可以检查产物完整性，不代表一般收件机的 Gatekeeper 会将其作为已认证的站外应用放行。最低 macOS 13.0 是编译目标，尚未跨版本实测。[Apple Developer ID](https://developer.apple.com/developer-id/)；[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 诊断

设置 → 关于与诊断可打开诊断目录。`~/Library/Glint/logs/glint.log` 与 `glint.previous.log` 各最多 1 MiB；记录启动、维护、下载、同步阶段和错误摘要，不逐键记录拼音或候选正文。写入由限量后台队列处理，失败不阻塞输入；强制退出前的最后几条不保证落盘。Rime 的原始日志由各方案目录另行保存。诊断先看实际输入源列表、服务启动、宿主真实激活与上屏，不从菜单勾选或日志缺失单独推断输入已成功或失败。
