// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// 只配置 Rime 官方预测组件。预测、排序、确认仍由原有 Rime 会话负责。
enum GlintPrediction {
  static let database = "glint-predict.db"

  static func installDatabase(in directory: URL) throws {
    try GlintBundledRime.installMissing(to: directory, only: database)
  }
}

extension GlintDataStore {
  /// 维护副本里部署并读回；同一拼音方案的全拼、双拼共用开关。
  func savePrediction(_ enabled: Bool, scheme: GlintInputScheme) throws -> String {
    let schemas = scheme == .ice ? GlintInputScheme.Layout.allCases.map(\.iceSchema) : ["wanxiang"]
    let customFiles = schemas.map { $0 + ".custom.yaml" }
    try transaction(paths: customFiles + [GlintPrediction.database, "build"]) { stage in
      try GlintPrediction.installDatabase(in: stage)
      for file in customFiles {
        let url = stage.appendingPathComponent(file)
        let data = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let existing = try RimeConfiguration.patch(data)
        // 保留用户的其它补丁；这些插入位置已被自定义组件占用时，不能覆盖它。
        for (key, component) in ["engine/processors/@before 0": "predictor",
                                  "engine/translators/@before 0": "predict_translator"] {
          if let old = existing[key], old as? String != component {
            throw GlintError.message("\(file) 的 \(key) 已有自定义配置，请先合并该位置后重试。")
          }
        }
        if let old = existing["switches/@next"], (old as? [String: Any])?["name"] as? String != "prediction" {
          throw GlintError.message("\(file) 已有自定义追加开关，请先合并 switches/@next 后重试。")
        }
        try RimeConfiguration.update(url, changes: [
          "engine/processors/@before 0": "predictor",
          "engine/translators/@before 0": "predict_translator",
          "switches/@next": ["name": "prediction", "states": ["关闭联想", "开启联想"], "reset": enabled ? 1 : 0],
          "predictor/db": GlintPrediction.database,
          "predictor/max_iterations": 0,
          "predictor/max_candidates": 8])
      }
      try Self.withEngine(at: stage, deploy: true) { engine in
        engine.openSession()
        // 只读取当前已部署方案；其它键位在原有切换事务中部署、验证。
        guard engine.option("prediction") == enabled else {
          throw GlintError.message("联想开关未生效，已保留原方案。")
        }
      }
    }
    return enabled ? "已开启上屏后联想；全拼、双拼均生效。" : "已关闭上屏后联想。"
  }
}
