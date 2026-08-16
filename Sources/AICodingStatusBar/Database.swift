import CSQLite
import Foundation

final class StatusDatabase {
  private var db: OpaquePointer?
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
      sqlite3_open_v2(
        url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else {
      throw NSError(
        domain: "StatusDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: lastError])
    }
    try exec("PRAGMA journal_mode=WAL")
    try exec("PRAGMA synchronous=NORMAL")
    try migrate()
  }

  deinit { sqlite3_close(db) }

  private var lastError: String {
    db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable"
  }
  private func exec(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? lastError
      sqlite3_free(error)
      throw NSError(
        domain: "StatusDatabase", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw NSError(
        domain: "StatusDatabase", code: 3, userInfo: [NSLocalizedDescriptionKey: lastError])
    }
    return statement
  }
  private func done(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NSError(
        domain: "StatusDatabase", code: 4, userInfo: [NSLocalizedDescriptionKey: lastError])
    }
  }
  private func bind(_ value: String?, _ index: Int32, _ statement: OpaquePointer) {
    if let value {
      sqlite3_bind_text(statement, index, value, -1, transient)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }
  private func bind(_ value: Int64?, _ index: Int32, _ statement: OpaquePointer) {
    if let value {
      sqlite3_bind_int64(statement, index, value)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }
  private func bind(_ value: Double?, _ index: Int32, _ statement: OpaquePointer) {
    if let value {
      sqlite3_bind_double(statement, index, value)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private func migrate() throws {
    try exec(
      """
      CREATE TABLE IF NOT EXISTS source_files (
        thread_id TEXT PRIMARY KEY,path TEXT NOT NULL,inode INTEGER NOT NULL,byte_offset INTEGER NOT NULL,
        file_size INTEGER NOT NULL,modified_at REAL NOT NULL,cumulative_input INTEGER NOT NULL,
        cumulative_output INTEGER NOT NULL,cumulative_total INTEGER NOT NULL,current_turn_id TEXT,
        baseline_input INTEGER NOT NULL,baseline_output INTEGER NOT NULL,baseline_total INTEGER NOT NULL,
        cwd TEXT NOT NULL,source_kind TEXT NOT NULL,is_primary INTEGER NOT NULL)
      """)
    try exec(
      """
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,thread_id TEXT NOT NULL,project TEXT NOT NULL,title TEXT NOT NULL,status TEXT NOT NULL,
        started_at REAL NOT NULL,completed_at REAL,duration_ms INTEGER,last_activity_at REAL NOT NULL,
        input_tokens INTEGER NOT NULL,output_tokens INTEGER NOT NULL,total_tokens INTEGER NOT NULL,
        is_primary INTEGER NOT NULL,source_kind TEXT NOT NULL,error_message TEXT)
      """)
    try exec("CREATE INDEX IF NOT EXISTS idx_tasks_recent ON tasks(started_at DESC)")
    try exec("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status,is_primary)")
    try exec(
      """
      CREATE TABLE IF NOT EXISTS token_events (
        thread_id TEXT NOT NULL,event_timestamp REAL NOT NULL,input_delta INTEGER NOT NULL,
        output_delta INTEGER NOT NULL,total_delta INTEGER NOT NULL,PRIMARY KEY(thread_id,event_timestamp))
      """)
    try exec(
      "CREATE INDEX IF NOT EXISTS idx_token_events_timestamp ON token_events(event_timestamp)")
    try exec(
      """
      CREATE TABLE IF NOT EXISTS weekly_limit (
        limit_id TEXT PRIMARY KEY,used_percent REAL NOT NULL,window_minutes INTEGER NOT NULL,
        resets_at REAL NOT NULL,fetched_at REAL NOT NULL,source TEXT NOT NULL)
      """)
  }

  func checkpoint(threadID: String) throws -> SourceCheckpoint? {
    let s = try prepare(
      "SELECT path,inode,byte_offset,file_size,modified_at,cumulative_input,cumulative_output,cumulative_total,current_turn_id,baseline_input,baseline_output,baseline_total,cwd,source_kind,is_primary FROM source_files WHERE thread_id=?"
    )
    defer { sqlite3_finalize(s) }
    bind(threadID, 1, s)
    guard sqlite3_step(s) == SQLITE_ROW else { return nil }
    return SourceCheckpoint(
      threadID: threadID,
      path: String(cString: sqlite3_column_text(s, 0)),
      inode: UInt64(sqlite3_column_int64(s, 1)),
      byteOffset: UInt64(sqlite3_column_int64(s, 2)),
      fileSize: UInt64(sqlite3_column_int64(s, 3)),
      modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
      cumulativeInput: sqlite3_column_int64(s, 5), cumulativeOutput: sqlite3_column_int64(s, 6),
      cumulativeTotal: sqlite3_column_int64(s, 7),
      currentTurnID: sqlite3_column_type(s, 8) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(s, 8)),
      baselineInput: sqlite3_column_int64(s, 9), baselineOutput: sqlite3_column_int64(s, 10),
      baselineTotal: sqlite3_column_int64(s, 11), cwd: String(cString: sqlite3_column_text(s, 12)),
      sourceKind: String(cString: sqlite3_column_text(s, 13)),
      isPrimary: sqlite3_column_int(s, 14) != 0
    )
  }

  func save(_ c: SourceCheckpoint) throws {
    let s = try prepare(
      """
      INSERT INTO source_files VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(thread_id) DO UPDATE SET path=excluded.path,inode=excluded.inode,byte_offset=excluded.byte_offset,
      file_size=excluded.file_size,modified_at=excluded.modified_at,cumulative_input=excluded.cumulative_input,
      cumulative_output=excluded.cumulative_output,cumulative_total=excluded.cumulative_total,
      current_turn_id=excluded.current_turn_id,baseline_input=excluded.baseline_input,
      baseline_output=excluded.baseline_output,baseline_total=excluded.baseline_total,cwd=excluded.cwd,
      source_kind=excluded.source_kind,is_primary=excluded.is_primary
      """)
    defer { sqlite3_finalize(s) }
    bind(c.threadID, 1, s)
    bind(c.path, 2, s)
    bind(Int64(c.inode), 3, s)
    bind(Int64(c.byteOffset), 4, s)
    bind(Int64(c.fileSize), 5, s)
    bind(c.modifiedAt.timeIntervalSince1970, 6, s)
    bind(c.cumulativeInput, 7, s)
    bind(c.cumulativeOutput, 8, s)
    bind(c.cumulativeTotal, 9, s)
    bind(c.currentTurnID, 10, s)
    bind(c.baselineInput, 11, s)
    bind(c.baselineOutput, 12, s)
    bind(c.baselineTotal, 13, s)
    bind(c.cwd, 14, s)
    bind(c.sourceKind, 15, s)
    bind(Int64(c.isPrimary ? 1 : 0), 16, s)
    try done(s)
  }

  func reset(threadID: String) throws {
    try exec("BEGIN IMMEDIATE")
    do {
      for table in ["tasks", "token_events", "source_files"] {
        let s = try prepare("DELETE FROM \(table) WHERE thread_id=?")
        bind(threadID, 1, s)
        try done(s)
        sqlite3_finalize(s)
      }
      try exec("COMMIT")
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }

  func task(id: String) throws -> CodingTask? {
    let s = try prepare("SELECT * FROM tasks WHERE id=?")
    defer { sqlite3_finalize(s) }
    bind(id, 1, s)
    return sqlite3_step(s) == SQLITE_ROW ? decode(s) : nil
  }

  func upsert(_ t: CodingTask) throws {
    let s = try prepare(
      """
      INSERT INTO tasks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET project=excluded.project,title=excluded.title,status=excluded.status,
      completed_at=excluded.completed_at,duration_ms=excluded.duration_ms,last_activity_at=excluded.last_activity_at,
      input_tokens=excluded.input_tokens,output_tokens=excluded.output_tokens,total_tokens=excluded.total_tokens,
      is_primary=excluded.is_primary,source_kind=excluded.source_kind,error_message=excluded.error_message
      """)
    defer { sqlite3_finalize(s) }
    bind(t.id, 1, s)
    bind(t.threadID, 2, s)
    bind(t.project, 3, s)
    bind(t.title, 4, s)
    bind(t.status.rawValue, 5, s)
    bind(t.startedAt.timeIntervalSince1970, 6, s)
    bind(t.completedAt?.timeIntervalSince1970, 7, s)
    bind(t.durationMilliseconds, 8, s)
    bind(t.lastActivityAt.timeIntervalSince1970, 9, s)
    bind(t.inputTokens, 10, s)
    bind(t.outputTokens, 11, s)
    bind(t.totalTokens, 12, s)
    bind(Int64(t.isPrimary ? 1 : 0), 13, s)
    bind(t.sourceKind, 14, s)
    bind(t.errorMessage, 15, s)
    try done(s)
  }

  func updateText(id: String, title: String, project: String) throws {
    let s = try prepare("UPDATE tasks SET title=?,project=? WHERE id=?")
    defer { sqlite3_finalize(s) }
    bind(title, 1, s)
    bind(project, 2, s)
    bind(id, 3, s)
    try done(s)
  }
  func updateActivity(id: String, at: Date) throws {
    let s = try prepare("UPDATE tasks SET last_activity_at=MAX(last_activity_at,?) WHERE id=?")
    defer { sqlite3_finalize(s) }
    bind(at.timeIntervalSince1970, 1, s)
    bind(id, 2, s)
    try done(s)
  }
  func insertTokens(threadID: String, at: Date, input: Int64, output: Int64, total: Int64) throws {
    let s = try prepare("INSERT OR IGNORE INTO token_events VALUES (?,?,?,?,?)")
    defer { sqlite3_finalize(s) }
    bind(threadID, 1, s)
    bind(at.timeIntervalSince1970, 2, s)
    bind(input, 3, s)
    bind(output, 4, s)
    bind(total, 5, s)
    try done(s)
  }

  func save(_ w: WeeklyLimit) throws {
    let s = try prepare(
      """
      INSERT INTO weekly_limit VALUES (?,?,?,?,?,?) ON CONFLICT(limit_id) DO UPDATE SET
      used_percent=excluded.used_percent,window_minutes=excluded.window_minutes,resets_at=excluded.resets_at,
      fetched_at=excluded.fetched_at,source=excluded.source
      WHERE (excluded.source='account' AND excluded.fetched_at>=weekly_limit.fetched_at)
         OR (weekly_limit.source!='account' AND excluded.fetched_at>=weekly_limit.fetched_at)
         OR (excluded.fetched_at-weekly_limit.fetched_at>1800)
      """)
    defer { sqlite3_finalize(s) }
    bind(w.limitID, 1, s)
    bind(w.usedPercent, 2, s)
    bind(Int64(w.windowMinutes), 3, s)
    bind(w.resetsAt.timeIntervalSince1970, 4, s)
    bind(w.fetchedAt.timeIntervalSince1970, 5, s)
    bind(w.source, 6, s)
    try done(s)
  }

  func weekly() throws -> WeeklyLimit? {
    let s = try prepare(
      "SELECT limit_id,used_percent,window_minutes,resets_at,fetched_at,source FROM weekly_limit WHERE limit_id='codex'"
    )
    defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { return nil }
    return WeeklyLimit(
      limitID: String(cString: sqlite3_column_text(s, 0)), usedPercent: sqlite3_column_double(s, 1),
      windowMinutes: Int(sqlite3_column_int(s, 2)),
      resetsAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)),
      fetchedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 4)),
      source: String(cString: sqlite3_column_text(s, 5)))
  }

  func running() throws -> [CodingTask] {
    try tasks("SELECT * FROM tasks WHERE status='running' ORDER BY last_activity_at DESC")
  }

  func conversations(limit: Int) throws -> [CodingTask] {
    let s = try prepare(
      """
      WITH ranked AS (SELECT *,ROW_NUMBER() OVER(PARTITION BY thread_id ORDER BY COALESCE(completed_at,last_activity_at) DESC,started_at DESC) rank FROM tasks WHERE is_primary=1),
      agg AS (SELECT thread_id,MIN(started_at) first_at,MAX(last_activity_at) last_at,SUM(input_tokens) input,SUM(output_tokens) output,SUM(total_tokens) total FROM tasks WHERE is_primary=1 GROUP BY thread_id)
      SELECT r.id,r.thread_id,r.project,r.title,r.status,a.first_at,CASE WHEN r.status='running' THEN NULL ELSE a.last_at END,
      CAST(MAX(0,(a.last_at-a.first_at)*1000) AS INTEGER),a.last_at,a.input,a.output,a.total,r.is_primary,r.source_kind,r.error_message
      FROM ranked r JOIN agg a ON a.thread_id=r.thread_id WHERE r.rank=1 ORDER BY a.last_at DESC LIMIT ?
      """)
    defer { sqlite3_finalize(s) }
    sqlite3_bind_int(s, 1, Int32(limit))
    var result: [CodingTask] = []
    while sqlite3_step(s) == SQLITE_ROW { result.append(decode(s)) }
    return result
  }

  func counts(start: Date, end: Date) throws -> (Int, Int) {
    let s = try prepare(
      "SELECT SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END),SUM(CASE WHEN status IN ('failed','interrupted') THEN 1 ELSE 0 END) FROM tasks WHERE is_primary=1 AND COALESCE(completed_at,last_activity_at)>=? AND COALESCE(completed_at,last_activity_at)<?"
    )
    defer { sqlite3_finalize(s) }
    bind(start.timeIntervalSince1970, 1, s)
    bind(end.timeIntervalSince1970, 2, s)
    guard sqlite3_step(s) == SQLITE_ROW else { return (0, 0) }
    return (Int(sqlite3_column_int(s, 0)), Int(sqlite3_column_int(s, 1)))
  }
  func usage(start: Date, end: Date) throws -> TokenUsage {
    let s = try prepare(
      "SELECT COALESCE(SUM(input_delta),0),COALESCE(SUM(output_delta),0),COALESCE(SUM(total_delta),0) FROM token_events WHERE event_timestamp>=? AND event_timestamp<?"
    )
    defer { sqlite3_finalize(s) }
    bind(start.timeIntervalSince1970, 1, s)
    bind(end.timeIntervalSince1970, 2, s)
    guard sqlite3_step(s) == SQLITE_ROW else { return .zero }
    return TokenUsage(
      inputTokens: sqlite3_column_int64(s, 0), outputTokens: sqlite3_column_int64(s, 1),
      totalTokens: sqlite3_column_int64(s, 2))
  }

  private func tasks(_ sql: String) throws -> [CodingTask] {
    let s = try prepare(sql)
    defer { sqlite3_finalize(s) }
    var result: [CodingTask] = []
    while sqlite3_step(s) == SQLITE_ROW { result.append(decode(s)) }
    return result
  }
  private func decode(_ s: OpaquePointer) -> CodingTask {
    CodingTask(
      id: String(cString: sqlite3_column_text(s, 0)),
      threadID: String(cString: sqlite3_column_text(s, 1)),
      project: String(cString: sqlite3_column_text(s, 2)),
      title: String(cString: sqlite3_column_text(s, 3)),
      status: TaskStatus(rawValue: String(cString: sqlite3_column_text(s, 4))) ?? .unknown,
      startedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
      completedAt: sqlite3_column_type(s, 6) == SQLITE_NULL
        ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
      durationMilliseconds: sqlite3_column_type(s, 7) == SQLITE_NULL
        ? nil : sqlite3_column_int64(s, 7),
      lastActivityAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
      inputTokens: sqlite3_column_int64(s, 9),
      outputTokens: sqlite3_column_int64(s, 10), totalTokens: sqlite3_column_int64(s, 11),
      isPrimary: sqlite3_column_int(s, 12) != 0,
      sourceKind: String(cString: sqlite3_column_text(s, 13)),
      errorMessage: sqlite3_column_type(s, 14) == SQLITE_NULL
        ? nil : String(cString: sqlite3_column_text(s, 14)))
  }
}
