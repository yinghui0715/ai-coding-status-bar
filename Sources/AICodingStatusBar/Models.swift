import Foundation

enum TaskStatus: String, Codable, Sendable {
  case running, completed, failed, interrupted, unknown
  var isFailure: Bool { self == .failed || self == .interrupted }
}

struct CodingTask: Identifiable, Hashable, Sendable {
  let id: String
  let threadID: String
  var project: String
  var title: String
  var status: TaskStatus
  var startedAt: Date
  var completedAt: Date?
  var durationMilliseconds: Int64?
  var lastActivityAt: Date
  var inputTokens: Int64
  var outputTokens: Int64
  var totalTokens: Int64
  var isPrimary: Bool
  var sourceKind: String
  var errorMessage: String?
}

struct TokenUsage: Sendable {
  var inputTokens: Int64
  var outputTokens: Int64
  var totalTokens: Int64
  static let zero = TokenUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
}

struct WeeklyLimit: Sendable {
  var limitID: String
  var usedPercent: Double
  var windowMinutes: Int
  var resetsAt: Date
  var fetchedAt: Date
  var source: String
  var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
  var isWeekly: Bool { windowMinutes == 10_080 }
}

struct DashboardSnapshot: Sendable {
  var runningTasks: [CodingTask]
  var completedToday: Int
  var failedToday: Int
  var todayUsage: TokenUsage
  var weeklyLimit: WeeklyLimit?
  var recentConversations: [CodingTask]
  var lastUpdatedAt: Date
  var collectorError: String?
  static let empty = DashboardSnapshot(
    runningTasks: [], completedToday: 0, failedToday: 0, todayUsage: .zero,
    weeklyLimit: nil, recentConversations: [], lastUpdatedAt: .distantPast,
    collectorError: nil
  )
}

struct SourceCheckpoint {
  var threadID: String
  var path: String
  var inode: UInt64
  var byteOffset: UInt64 = 0
  var fileSize: UInt64 = 0
  var modifiedAt: Date
  var cumulativeInput: Int64 = 0
  var cumulativeOutput: Int64 = 0
  var cumulativeTotal: Int64 = 0
  var currentTurnID: String?
  var baselineInput: Int64 = 0
  var baselineOutput: Int64 = 0
  var baselineTotal: Int64 = 0
  var cwd: String = ""
  var sourceKind: String = "unknown"
  var isPrimary: Bool = true
}
