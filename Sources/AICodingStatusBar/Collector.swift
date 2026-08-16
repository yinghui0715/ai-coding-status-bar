import Foundation

actor CodexCollector {
  private let environment: CodexEnvironment
  private let home: URL
  private let db: StatusDatabase
  private let parser: JSONLParser
  private let locks: WriterLockChecker
  private let account: AccountClient

  init(environment: CodexEnvironment = .discover()) throws {
    self.environment = environment
    home = environment.dataHome
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    db = try StatusDatabase(url: base.appendingPathComponent("AICodingStatusBar/status.sqlite"))
    parser = JSONLParser(db: db, projects: ProjectResolver(stateURLs: environment.projectStateURLs))
    locks = WriterLockChecker(
      directory: home.appendingPathComponent("thread-writer-locks", isDirectory: true))
    account = AccountClient(executableURL: environment.executableURL)
  }

  func refresh() -> DashboardSnapshot {
    var message =
      environment.sessionRoots.contains {
        FileManager.default.fileExists(atPath: $0.path)
      } ? nil : "No Codex sessions found in \(home.path)"
    do { try importSessions() } catch { message = error.localizedDescription }
    do { return try snapshot(error: message) } catch {
      return DashboardSnapshot(
        runningTasks: [], completedToday: 0, failedToday: 0, todayUsage: .zero,
        weeklyLimit: try? db.weekly(), recentConversations: [], lastUpdatedAt: Date(),
        collectorError: message ?? error.localizedDescription)
    }
  }
  func refreshAccount() -> DashboardSnapshot {
    do {
      if let weekly = try account.fetch() { try db.save(weekly) }
      return try snapshot(error: nil)
    } catch {
      var s = refresh()
      s.collectorError = "Account usage unavailable: \(error.localizedDescription)"
      return s
    }
  }

  private func importSessions() throws {
    for file in try discover() {
      let stored = try db.checkpoint(threadID: file.threadID)
      var c =
        stored
        ?? SourceCheckpoint(
          threadID: file.threadID, path: file.url.path, inode: file.inode,
          modifiedAt: file.modifiedAt)
      var save = stored == nil
      if c.inode != file.inode || file.size < c.byteOffset {
        try db.reset(threadID: file.threadID)
        c = SourceCheckpoint(
          threadID: file.threadID, path: file.url.path, inode: file.inode,
          modifiedAt: file.modifiedAt)
        save = true
      }
      if c.path != file.url.path || c.inode != file.inode || c.fileSize != file.size
        || c.modifiedAt != file.modifiedAt
      {
        save = true
      }
      c.path = file.url.path
      c.inode = file.inode
      if file.size > c.byteOffset
        && (stored == nil || file.size != c.fileSize || file.modifiedAt != c.modifiedAt)
      {
        c = try parser.parse(url: file.url, checkpoint: c, maximumOffset: file.size)
        save = true
      }
      c.fileSize = file.size
      c.modifiedAt = file.modifiedAt
      if save { try db.save(c) }
    }
  }
  private func snapshot(error: String?) throws -> DashboardSnapshot {
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let stored = try db.running()
    var running: [CodingTask] = []
    var interrupted: [String: CodingTask] = [:]
    var unknown: [String: CodingTask] = [:]
    for var task in stored {
      switch locks.state(threadID: task.threadID) {
      case .held: running.append(task)
      case .free:
        task.status = .interrupted
        interrupted[task.id] = task
      case .unavailable:
        task.status = .unknown
        unknown[task.id] = task
      }
    }
    var recent = try db.conversations(limit: 24).map { interrupted[$0.id] ?? unknown[$0.id] ?? $0 }
    let active = Dictionary(uniqueKeysWithValues: running.map { ($0.id, $0) })
    recent = recent.map { active[$0.id] ?? $0 }
    let counts = try db.counts(start: start, end: end)
    let inferred = interrupted.values.filter {
      $0.isPrimary && $0.lastActivityAt >= start && $0.lastActivityAt < end
    }.count
    return DashboardSnapshot(
      runningTasks: running.sorted { $0.lastActivityAt > $1.lastActivityAt },
      completedToday: counts.0, failedToday: counts.1 + inferred,
      todayUsage: try db.usage(start: start, end: end), weeklyLimit: try db.weekly(),
      recentConversations: Array(recent.prefix(12)), lastUpdatedAt: now, collectorError: error)
  }
  private func discover() throws -> [SessionFile] {
    let roots = environment.sessionRoots
    var map: [String: SessionFile] = [:]
    for root in roots where FileManager.default.fileExists(atPath: root.path) {
      guard
        let e = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
      else { continue }
      for case let url as URL in e where url.pathExtension == "jsonl" {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.count >= 36 else { continue }
        let id = String(stem.suffix(36)).lowercased()
        guard UUID(uuidString: id) != nil else { continue }
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        let f = SessionFile(
          url: url, threadID: id, inode: (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
          size: (a[.size] as? NSNumber)?.uint64Value ?? 0,
          modifiedAt: a[.modificationDate] as? Date ?? .distantPast)
        if map[id] == nil || f.modifiedAt > map[id]!.modifiedAt { map[id] = f }
      }
    }
    return map.values.sorted { $0.modifiedAt < $1.modifiedAt }
  }
}

private struct SessionFile {
  var url: URL
  var threadID: String
  var inode: UInt64
  var size: UInt64
  var modifiedAt: Date
}

private final class AccountClient: @unchecked Sendable {
  private let executableURL: URL?
  init(executableURL: URL?) { self.executableURL = executableURL }

  func fetch() throws -> WeeklyLimit? {
    guard let executableURL else { return nil }
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    let stream = RPCStream()
    process.executableURL = executableURL
    process.arguments = ["app-server", "--listen", "stdio://"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    output.fileHandleForReading.readabilityHandler = { stream.append($0.availableData) }
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    let request =
      [
        "{\"method\":\"initialize\",\"id\":0,\"params\":{\"clientInfo\":{\"name\":\"ai_coding_status_bar\",\"version\":\"\(version)\"}}}",
        "{\"method\":\"initialized\",\"params\":{}}",
        "{\"method\":\"account/rateLimits/read\",\"id\":2,\"params\":{}}",
      ].joined(separator: "\n") + "\n"
    input.fileHandleForWriting.write(Data(request.utf8))
    let ok = stream.wait()
    output.fileHandleForReading.readabilityHandler = nil
    try? input.fileHandleForWriting.close()
    if process.isRunning { process.terminate() }
    guard ok else {
      throw NSError(
        domain: "AccountClient", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "rate-limit request timed out"])
    }
    for line in String(decoding: stream.data, as: UTF8.self).split(whereSeparator: \.isNewline) {
      guard let d = String(line).data(using: .utf8),
        let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
        (m["id"] as? NSNumber)?.intValue == 2, let result = m["result"] as? [String: Any],
        let limits = result["rateLimits"] as? [String: Any],
        let primary = limits["primary"] as? [String: Any]
      else { continue }
      func number(_ x: Any?) -> Double {
        if let n = x as? NSNumber { return n.doubleValue }
        if let s = x as? String { return Double(s) ?? 0 }
        return 0
      }
      let reset = number(primary["resetsAt"])
      guard reset > 0 else { return nil }
      return WeeklyLimit(
        limitID: limits["limitId"] as? String ?? "codex",
        usedPercent: number(primary["usedPercent"]),
        windowMinutes: Int(number(primary["windowDurationMins"])),
        resetsAt: Date(timeIntervalSince1970: reset), fetchedAt: Date(), source: "account")
    }
    return nil
  }
}

private final class RPCStream: @unchecked Sendable {
  private let lock = NSLock(), semaphore = DispatchSemaphore(value: 0)
  private var storage = Data(), buffer = Data(), done = false
  var data: Data { lock.withLock { storage } }
  func append(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.withLock {
      storage.append(data)
      buffer.append(data)
      while let n = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[..<n])
        buffer.removeSubrange(buffer.startIndex...n)
        if let m = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          (m["id"] as? NSNumber)?.intValue == 2, !done
        {
          done = true
          semaphore.signal()
        }
      }
    }
  }
  func wait() -> Bool { semaphore.wait(timeout: .now() + 20) == .success }
}
