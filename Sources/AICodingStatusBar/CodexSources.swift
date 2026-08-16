import Darwin
import Foundation

struct ProjectResolver {
  private let mappings: [(path: String, name: String)]
  init(stateURLs: [URL]) {
    guard let url = stateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
      let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let projects = root["local-projects"] as? [String: Any]
    else {
      mappings = []
      return
    }
    var values: [(String, String)] = []
    for raw in projects.values {
      guard let p = raw as? [String: Any], let name = p["name"] as? String,
        let roots = p["rootPaths"] as? [String]
      else { continue }
      values.append(contentsOf: roots.map { ($0, name) })
    }
    mappings = values.sorted { $0.0.count > $1.0.count }.map { ($0.0, $0.1) }
  }
  func name(cwd: String) -> String {
    let path = URL(fileURLWithPath: cwd).standardizedFileURL.path
    if let hit = mappings.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
      return hit.name
    }
    let last = URL(fileURLWithPath: cwd).lastPathComponent
    return last.isEmpty ? "Codex" : last
  }
}

enum LockState { case held, free, unavailable }
struct WriterLockChecker {
  let directory: URL
  func state(threadID: String) -> LockState {
    let fd = open(directory.appendingPathComponent("\(threadID).lock").path, O_RDONLY)
    guard fd >= 0 else { return errno == ENOENT ? .free : .unavailable }
    defer { close(fd) }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 {
      flock(fd, LOCK_UN)
      return .free
    }
    return errno == EWOULDBLOCK ? .held : .unavailable
  }
}

final class JSONLParser {
  let db: StatusDatabase
  let projects: ProjectResolver
  private let fractional: ISO8601DateFormatter
  private let standard: ISO8601DateFormatter
  init(db: StatusDatabase, projects: ProjectResolver) {
    self.db = db
    self.projects = projects
    fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
  }
  func parse(url: URL, checkpoint original: SourceCheckpoint, maximumOffset: UInt64) throws
    -> SourceCheckpoint
  {
    var c = original
    let h = try FileHandle(forReadingFrom: url)
    defer { try? h.close() }
    try h.seek(toOffset: c.byteOffset)
    var buffer = Data()
    var readOffset = c.byteOffset
    var consumed = c.byteOffset
    while readOffset < maximumOffset {
      let count = Int(min(UInt64(256 * 1024), maximumOffset - readOffset))
      guard let chunk = try h.read(upToCount: count), !chunk.isEmpty else { break }
      readOffset += UInt64(chunk.count)
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = Data(buffer[..<newline])
        let amount = buffer.distance(from: buffer.startIndex, to: buffer.index(after: newline))
        buffer.removeSubrange(buffer.startIndex...newline)
        consumed += UInt64(amount)
        if !line.isEmpty { try consume(line, &c) }
      }
    }
    c.byteOffset = consumed
    return c
  }
  private func consume(_ line: Data, _ c: inout SourceCheckpoint) throws {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let type = object["type"] as? String
    else { return }
    let at = date(object["timestamp"]) ?? Date()
    if let turn = c.currentTurnID { try db.updateActivity(id: turn, at: at) }
    guard let p = object["payload"] as? [String: Any] else { return }
    switch type {
    case "session_meta":
      if let cwd = p["cwd"] as? String { c.cwd = cwd }
      if let source = p["source"] as? String {
        c.sourceKind = source
        c.isPrimary = !source.lowercased().contains("subagent")
      } else if let source = p["source"] as? [String: Any], source["subagent"] != nil {
        c.sourceKind = "subagent"
        c.isPrimary = false
      }
    case "turn_context":
      if let cwd = p["cwd"] as? String { c.cwd = cwd }
    case "event_msg": try event(p, at, &c)
    default: break
    }
  }
  private func event(_ p: [String: Any], _ at: Date, _ c: inout SourceCheckpoint) throws {
    guard let type = p["type"] as? String else { return }
    switch type {
    case "task_started":
      guard let id = p["turn_id"] as? String else { return }
      c.currentTurnID = id
      c.baselineInput = c.cumulativeInput
      c.baselineOutput = c.cumulativeOutput
      c.baselineTotal = c.cumulativeTotal
      try db.upsert(
        CodingTask(
          id: id, threadID: c.threadID, project: projects.name(cwd: c.cwd), title: "Codex Task",
          status: .running,
          startedAt: epoch(p["started_at"]) ?? at, completedAt: nil, durationMilliseconds: nil,
          lastActivityAt: at,
          inputTokens: 0, outputTokens: 0, totalTokens: 0, isPrimary: c.isPrimary,
          sourceKind: c.sourceKind, errorMessage: nil))
    case "user_message":
      if let id = c.currentTurnID, let message = p["message"] as? String {
        try db.updateText(id: id, title: title(message), project: projects.name(cwd: c.cwd))
      }
    case "token_count": try tokens(p, at, &c)
    case "task_complete": try finish(p, at, .completed, nil, &c)
    case "turn_aborted":
      let reason = p["reason"] as? String ?? "interrupted"
      try finish(p, at, reason == "interrupted" ? .interrupted : .failed, reason, &c)
    case "stream_error", "error":
      if let id = c.currentTurnID, var task = try db.task(id: id) {
        task.status = .failed
        task.lastActivityAt = at
        task.errorMessage = p["message"] as? String ?? "Codex error"
        try db.upsert(task)
      }
    default: break
    }
  }
  private func tokens(_ p: [String: Any], _ at: Date, _ c: inout SourceCheckpoint) throws {
    if let info = p["info"] as? [String: Any],
      let total = info["total_token_usage"] as? [String: Any]
    {
      let i = int(total["input_tokens"])
      let o = int(total["output_tokens"])
      let t = int(total["total_tokens"])
      let di = i >= c.cumulativeInput ? i - c.cumulativeInput : i
      let outputDelta = o >= c.cumulativeOutput ? o - c.cumulativeOutput : o
      let dt = t >= c.cumulativeTotal ? t - c.cumulativeTotal : t
      if di > 0 || outputDelta > 0 || dt > 0 {
        try db.insertTokens(
          threadID: c.threadID,
          at: at,
          input: di,
          output: outputDelta,
          total: dt
        )
      }
      c.cumulativeInput = i
      c.cumulativeOutput = o
      c.cumulativeTotal = t
      if let id = c.currentTurnID, var task = try db.task(id: id) {
        task.inputTokens = max(0, i - c.baselineInput)
        task.outputTokens = max(0, o - c.baselineOutput)
        task.totalTokens = max(0, t - c.baselineTotal)
        task.lastActivityAt = at
        try db.upsert(task)
      }
    }
    if let limits = p["rate_limits"] as? [String: Any],
      let primary = limits["primary"] as? [String: Any], let reset = epoch(primary["resets_at"])
    {
      try db.save(
        WeeklyLimit(
          limitID: limits["limit_id"] as? String ?? "codex",
          usedPercent: double(primary["used_percent"]),
          windowMinutes: Int(int(primary["window_minutes"])), resetsAt: reset, fetchedAt: at,
          source: "session"))
    }
  }
  private func finish(
    _ p: [String: Any], _ at: Date, _ status: TaskStatus, _ error: String?,
    _ c: inout SourceCheckpoint
  ) throws {
    guard let id = p["turn_id"] as? String, var task = try db.task(id: id) else { return }
    task.status = status
    task.completedAt = epoch(p["completed_at"]) ?? at
    task.durationMilliseconds = optionalInt(p["duration_ms"])
    task.lastActivityAt = at
    task.errorMessage = error
    try db.upsert(task)
    if c.currentTurnID == id { c.currentTurnID = nil }
  }
  private func title(_ message: String) -> String {
    let lines = message.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let markers = ["# my request:", "## my request:", "my request:"]
    let start =
      lines.lastIndex(where: { markers.contains($0.lowercased()) }).map { lines.index(after: $0) }
      ?? lines.startIndex
    let ignored = [
      "# files mentioned by the user:", "## files mentioned by the user:",
      "# images mentioned by the user:", "![image",
    ]
    let value =
      lines[start...].first { v in
        let l = v.lowercased()
        return !v.isEmpty && !v.hasPrefix("<") && !v.hasPrefix("## ")
          && !ignored.contains(where: l.hasPrefix)
      } ?? "Codex Task"
    return value.count <= 120 ? value : String(value.prefix(117)) + "…"
  }
  private func date(_ raw: Any?) -> Date? {
    guard let s = raw as? String else { return nil }
    return fractional.date(from: s) ?? standard.date(from: s)
  }
  private func epoch(_ raw: Any?) -> Date? {
    let v = double(raw)
    return v > 0 ? Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v) : nil
  }
  private func int(_ raw: Any?) -> Int64 {
    if let n = raw as? NSNumber { return n.int64Value }
    if let s = raw as? String { return Int64(s) ?? 0 }
    return 0
  }
  private func optionalInt(_ raw: Any?) -> Int64? { raw == nil ? nil : int(raw) }
  private func double(_ raw: Any?) -> Double {
    if let n = raw as? NSNumber { return n.doubleValue }
    if let s = raw as? String { return Double(s) ?? 0 }
    return 0
  }
}
