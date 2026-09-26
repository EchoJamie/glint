// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// 下载与解包不持有 Rime，不占用输入维护队列。回调统一在主线程。
final class GlintSchemeDownload: NSObject, URLSessionDownloadDelegate {
  private let scheme: GlintInputScheme
  let work: URL
  private let progress: (String) -> Void
  private let completion: (Result<URL, Error>) -> Void
  private var index = 0
  private var received: Int64 = 0
  private var lastProgress = Date.distantPast
  private var cancelled = false
  private var finished = false
  private let lock = NSLock()
  private var session: URLSession!
  private var task: URLSessionDownloadTask?

  init(scheme: GlintInputScheme, root: URL, progress: @escaping (String) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
    self.scheme = scheme; self.progress = progress; self.completion = completion
    work = root.appendingPathComponent(".glint-downloads/" + UUID().uuidString)
    super.init()
  }
  func start() {
    GlintLog.write("download", "begin scheme=\(scheme.rawValue) version=\(scheme.version)")
    do { try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true) }
    catch { GlintLog.write("download", "prepare_failed", error: error); completion(.failure(error)); return }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 3600
    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    next()
  }
  func cancel() {
    lock.lock(); cancelled = true; let task = self.task; lock.unlock()
    task?.cancel()
  }
  private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  private func next() {
    if isCancelled { finish(.failure(CancellationError())); return }
    GlintLog.write("download", "asset_begin scheme=\(scheme.rawValue) index=\(index)")
    let request = URLRequest(url: scheme.assets[index].url)
    let task = session.downloadTask(with: request)
    lock.lock(); self.task = task; let stop = cancelled; lock.unlock()
    task.resume()
    if stop { task.cancel() }
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    if totalBytesWritten > scheme.assets[index].size { downloadTask.cancel(); return }
    guard Date().timeIntervalSince(lastProgress) > 0.2 else { return }
    lastProgress = Date()
    let done = received + totalBytesWritten, total = scheme.assets.reduce(Int64(0)) { $0 + $1.size }
    let message = "正在下载 \(scheme.name)：\(ByteCountFormatter.string(fromByteCount: done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    DispatchQueue.main.async { self.progress(message) }
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    do {
      guard !isCancelled else { throw CancellationError() }
      GlintLog.write("download", "asset_received scheme=\(scheme.rawValue) index=\(index) http=\((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)")
      guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw GlintError.message("方案下载失败，请检查网络后重试。") }
      let asset = scheme.assets[index]
      try asset.verify(location)
      try FileManager.default.moveItem(at: location, to: work.appendingPathComponent(asset.name))
      received += asset.size; index += 1
      GlintLog.write("download", "asset_verified scheme=\(scheme.rawValue) completed=\(index)")
      if index < scheme.assets.count { next(); return }
      DispatchQueue.main.async { self.progress("下载完成，正在解包…") }
      let data = work.appendingPathComponent("data")
      GlintLog.write("download", "unpack_begin scheme=\(scheme.rawValue)")
      try scheme.unpack(downloads: work, to: data)
      guard !isCancelled else { throw CancellationError() }
      finish(.success(data))
    } catch { finish(.failure(error)) }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error { finish(.failure(isCancelled ? CancellationError() : error)) }
  }
  private func finish(_ result: Result<URL, Error>) {
    // 取消可与下载完成交错；完成只通知一次。
    guard !finished else { return }
    finished = true
    switch result {
    case .success: GlintLog.write("download", "complete scheme=\(scheme.rawValue)")
    case .failure(let error): GlintLog.write("download", "failed_or_cancelled scheme=\(scheme.rawValue)", error: error)
    }
    session.finishTasksAndInvalidate()
    if case .failure = result { try? FileManager.default.removeItem(at: work) }
    DispatchQueue.main.async { self.completion(result) }
  }
}
