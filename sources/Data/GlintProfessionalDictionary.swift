// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 首版专业词库作用于随包的 rime_ice 全拼词典。只插入带标记的 import_tables 行，
/// 用户的源文件、注释、其余配置保持原文，不修改学习库。
struct GlintProfessionalDictionary {
  struct Resource: Codable {
    let name: String
    let file: String
    let data: Data
    let dependencies: [String]
    let entries: Int
    let invalidLines: [Int]

    init(file: String, data: Data) throws {
      guard file.hasSuffix(".dict.yaml"), GlintDataStore.safeName(file),
            let source = String(data: data, encoding: .utf8), !source.contains("\0"),
            let delimiter = source.range(of: "(?m)^\\.\\.\\.[ \t]*$", options: .regularExpression) else {
        throw GlintError.message("词典需为 UTF-8 的 .dict.yaml，包含以 ... 结束的 YAML 声明。")
      }
      let header = String(source[..<delimiter.lowerBound])
      guard glint_rime_validate_yaml(header) == 0 else { throw GlintError.message("词典声明格式错误：\(file)") }
      var buffer = [CChar](repeating: 0, count: 65536)
      guard glint_rime_yaml_value(header, "name", &buffer, buffer.count) == 0 else { throw GlintError.message("词典缺少 name。") }
      let name = String(cString: buffer)
      guard GlintDataStore.safeName(name), file == name + ".dict.yaml", name != "rime_ice" else {
        throw GlintError.message("词典 name 必须与文件名一致，且不能覆盖基线词典。")
      }
      guard glint_rime_yaml_list(header, "columns", &buffer, buffer.count) == 0 else { throw GlintError.message("无法解析词典列声明。") }
      let columns = String(cString: buffer).split(separator: "\n").map(String.init)
      guard columns.isEmpty || columns == ["text", "code", "weight"] || columns == ["text", "code"] else {
        throw GlintError.message("首版支持 text、code、weight 顺序的全拼词典。")
      }
      guard glint_rime_yaml_list(header, "import_tables", &buffer, buffer.count) == 0 else { throw GlintError.message("词典依赖格式错误。") }
      let dependencies = String(cString: buffer).split(separator: "\n").map(String.init)
      guard dependencies.allSatisfy(Self.safeReference) else { throw GlintError.message("词典依赖包含目录越界。") }
      var count = 0, invalid: [Int] = []
      let prefixLines = source[..<delimiter.upperBound].filter { $0 == "\n" }.count
      for (index, line) in source[delimiter.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        var valid = (1...3).contains(fields.count) && !fields[0].isEmpty
        if fields.count >= 2 {
          // 全拼编码以音节空格分隔，不能把双拼/形码词库悄悄挂到全拼词典。
          valid = valid && fields[1].range(of: "^[A-Za-z]+(?: +[A-Za-z]+)*$", options: .regularExpression) != nil
        }
        if fields.count == 3 {
          let weight = fields[2].hasSuffix("%") ? String(fields[2].dropLast()) : fields[2]
          valid = valid && Double(weight).map { $0.isFinite && $0 >= 0 } == true
        }
        if valid { count += 1 } else { invalid.append(prefixLines + index + 1) }
      }
      self.name = name; self.file = file; self.data = data; self.dependencies = dependencies
      entries = count; invalidLines = invalid
    }
    static func safeReference(_ value: String) -> Bool {
      !value.hasPrefix("/") && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { GlintDataStore.safeName(String($0)) }
    }
  }
  struct Entry: Codable { let name: String; let file: String; let sha256: String; var enabled: Bool; let dependencies: [String] }
  let store: GlintDataStore
  private let fm = FileManager.default
  private let registryName = "glint-professional.json"

  func entries() throws -> [Entry] {
    let path = store.directory.appendingPathComponent(registryName)
    let entries = fm.fileExists(atPath: path.path) ? try JSONDecoder().decode([Entry].self, from: Data(contentsOf: path)) : []
    guard entries.allSatisfy({ GlintDataStore.safeName($0.name) && $0.file == $0.name + ".dict.yaml" &&
      $0.dependencies.allSatisfy(Resource.safeReference) }) else { throw GlintError.message("专业词库清单无效。") }
    return entries
  }

  func validate(_ resources: [Resource]) throws {
    guard !resources.isEmpty, Set(resources.map(\.name)).count == resources.count else { throw GlintError.message("词库包为空或名称重复。") }
    for resource in resources {
      guard resource.invalidLines.isEmpty else { throw GlintError.message("\(resource.file) 有 \(resource.invalidLines.count) 条无效记录：\(resource.invalidLines.prefix(8))") }
      guard !fm.fileExists(atPath: store.directory.appendingPathComponent(resource.file).path) else {
        throw GlintError.message("已存在同名词典，未覆盖：\(resource.file)")
      }
      for dependency in resource.dependencies {
        guard resources.contains(where: { $0.name == dependency }) ||
          fm.fileExists(atPath: store.directory.appendingPathComponent(dependency + ".dict.yaml").path) else {
          throw GlintError.message("缺少依赖：\(dependency).dict.yaml，请一起选择导入。")
        }
      }
    }
    // 依赖循环在编译前报告。
    func visit(_ name: String, stack: Set<String>) throws {
      guard !stack.contains(name) else { throw GlintError.message("词典依赖形成循环：\(name)") }
      guard let resource = resources.first(where: { $0.name == name }) else { return }
      for dependency in resource.dependencies { try visit(dependency, stack: stack.union([name])) }
    }
    for resource in resources { try visit(resource.name, stack: []) }
  }

  func install(_ resources: [Resource]) throws -> String {
    try validate(resources)
    var next = try entries()
    next += resources.map { Entry(name: $0.name, file: $0.file, sha256: GlintDataStore.hash($0.data), enabled: true, dependencies: $0.dependencies) }
    return try apply(next, resources: resources)
  }
  func setEnabled(_ name: String, enabled: Bool) throws -> String {
    var next = try entries()
    guard let index = next.firstIndex(where: { $0.name == name }) else { throw GlintError.message("词典已不存在。") }
    if enabled, next[index].dependencies.contains(where: { dependency in next.contains { $0.name == dependency && !$0.enabled } }) {
      throw GlintError.message("请先启用此词库依赖的词库。")
    }
    next[index].enabled = enabled
    if !enabled, next.contains(where: { $0.enabled && $0.dependencies.contains(name) }) {
      throw GlintError.message("仍有已启用词库依赖此词典，请先停用依赖它的词库。")
    }
    return try apply(next, resources: [])
  }
  private func apply(_ entries: [Entry], resources: [Resource]) throws -> String {
    try store.transaction(paths: resources.map(\.file) + [registryName, "rime_ice.dict.yaml", "build"]) { stage in
      for resource in resources { try resource.data.write(to: stage.appendingPathComponent(resource.file), options: .atomic) }
      let root = stage.appendingPathComponent("rime_ice.dict.yaml")
      let original = try String(contentsOf: root, encoding: .utf8)
      let updated = try Self.updateImports(original, names: entries.filter(\.enabled).map(\.name))
      try Data(updated.utf8).write(to: root, options: .atomic)
      try JSONEncoder().encode(entries).write(to: stage.appendingPathComponent(registryName), options: .atomic)
      // 删除副本的旧编译结果，确保依赖/编码错误不能由旧产物掩盖。
      try GlintDataStore.withEngine(at: stage, deploy: true) { engine in
        engine.openSession()
        guard let schema = engine.schemaID, RimeEngine.schemaValue(schema, key: "translator/dictionary") == "rime_ice" else {
          throw GlintError.message("当前方案未使用 rime_ice 全拼词典，未应用本次更改。")
        }
      }
      return "专业词库已应用：\(entries.filter(\.enabled).count) 个启用；个人学习库保持原样。"
    }
  }

  static func updateImports(_ source: String, names: [String]) throws -> String {
    let begin = "  # BEGIN GLINT PROFESSIONAL\n", end = "  # END GLINT PROFESSIONAL\n"
    var text = source
    if let start = text.range(of: begin) {
      guard let finish = text.range(of: end, range: start.upperBound..<text.endIndex) else { throw GlintError.message("托管词库标记不完整，请保留原文件并检查。") }
      text.removeSubrange(start.lowerBound..<finish.upperBound)
    } else if text.contains(end) { throw GlintError.message("托管词库标记不完整。") }
    guard !text.contains(begin), !text.contains(end),
      let insertion = text.range(of: "(?m)^import_tables:[ \\t]*\\n", options: .regularExpression) else {
      throw GlintError.message("基线词典 import_tables 不是可托管的分行列表，原文件未改动。")
    }
    if !names.isEmpty { text.insert(contentsOf: begin + names.map { "  - " + $0 + "\n" }.joined() + end, at: insertion.upperBound) }
    return text
  }

  func export(_ name: String, to destination: URL) throws -> String {
    let all = try entries()
    guard let selected = all.first(where: { $0.name == name }) else { throw GlintError.message("词典不存在。") }
    var included: [Entry] = [], seen = Set<String>()
    func collect(_ entry: Entry) {
      guard seen.insert(entry.name).inserted else { return }
      included.append(entry)
      for dependency in entry.dependencies { if let child = all.first(where: { $0.name == dependency }) { collect(child) } }
    }
    collect(selected)
    guard !fm.fileExists(atPath: destination.path) else { throw GlintError.message("导出目录已存在，请选择新目录。") }
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    for entry in included { try fm.copyItem(at: store.directory.appendingPathComponent(entry.file), to: destination.appendingPathComponent(entry.file)) }
    let external = Set(included.flatMap(\.dependencies)).subtracting(included.map(\.name)).sorted()
    let declaration = "Glint 专业词库：\(name)\n目标：rime_ice 全拼词典\n附带：\(included.map(\.file).joined(separator: "、"))\n需要基线依赖：\(external.joined(separator: "、"))\n原文件头部的作者、来源与许可证声明保持原文；分享前请核对其授权。\n"
    try Data(declaration.utf8).write(to: destination.appendingPathComponent("README.txt"), options: .atomic)
    return "已导出源词典、附带依赖和资源声明。"
  }
}
