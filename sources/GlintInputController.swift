//
//  GlintInputController.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import InputMethodKit

/// 系统输入接入层。
///
/// **T0.1 范围**：只建立会话通道并证明其可用，不处理输入内容。
/// 按键一律原样交回系统，因此即便输入源被启用也不会打断正常打字。
///
/// **尚未实现**（后续任务，不在 T0.1）：
/// - Rime 会话生命周期、预编辑文本与提交 —— T0.2 候选协议
/// - 候选窗口与 Touch Bar —— T0.3 / T0.4
/// - 中英文切换的既定为「原始拼音上屏后切换」—— M1
///
/// 参考实现见 `rime/squirrel` @ `0cd71a61` 的 `sources/SquirrelInputController.swift`。
/// 本文件尚未复用其代码；按 `docs/decisions.md` 5.2 节，实际复用后须补来源与修改说明。
final class GlintInputController: IMKInputController {
  override func activateServer(_ sender: Any!) {
    super.activateServer(sender)
    log("activateServer: \(clientBundleID(sender) ?? "unknown")")
  }

  override func deactivateServer(_ sender: Any!) {
    log("deactivateServer: \(clientBundleID(sender) ?? "unknown")")
    super.deactivateServer(sender)
  }

  /// 一律返回 false，把按键交回系统默认处理。
  ///
  /// T0.2 起这里才会接管与当前组合相关的按键；在此之前保持完全透明。
  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    false
  }

  /// 不产生组合文本。T0.2 接入 Rime 后由引擎的预编辑与提交驱动。
  override func inputText(_ string: String!, client sender: Any!) -> Bool {
    false
  }

  override func commitComposition(_ sender: Any!) {
    log("commitComposition")
    super.commitComposition(sender)
  }

  // MARK: - 诊断

  private func clientBundleID(_ sender: Any!) -> String? {
    guard let client = sender as? IMKTextInput else { return nil }
    return client.bundleIdentifier()
  }

  /// 诊断输出走 stderr，由 `scripts/run-dev.sh` 收进日志文件。
  ///
  /// 记录默认只含事件类别，**不含实际输入正文**（`docs/implementation-plan.md` §7）。
  private func log(_ message: String) {
    FileHandle.standardError.write(Data("[glint] \(message)\n".utf8))
  }
}
