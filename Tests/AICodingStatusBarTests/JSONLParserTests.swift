import Foundation
import XCTest

@testable import AICodingStatusBar

final class JSONLParserTests: XCTestCase {
  func testParsesTaskTitleStatusAndTokenDeltas() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let database = try StatusDatabase(url: directory.appendingPathComponent("status.sqlite"))
    let parser = JSONLParser(
      db: database,
      projects: ProjectResolver(stateURLs: [])
    )
    let threadID = "11111111-1111-1111-1111-111111111111"
    let turnID = "22222222-2222-2222-2222-222222222222"
    let sessionURL = directory.appendingPathComponent("session-\(threadID).jsonl")
    let lines = [
      ##"{"timestamp":"2026-08-16T01:00:00Z","type":"session_meta","payload":{"cwd":"/tmp/sample-workspace","source":"cli"}}"##,
      ##"{"timestamp":"2026-08-16T01:00:01Z","type":"event_msg","payload":{"type":"task_started","turn_id":"\##(turnID)"}}"##,
      ##"{"timestamp":"2026-08-16T01:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"# Files mentioned by the user:\n# My request:\nBuild a usage dashboard"}}"##,
      ##"{"timestamp":"2026-08-16T01:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120}}}}"##,
      ##"{"timestamp":"2026-08-16T01:00:04Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"\##(turnID)"}}"##,
    ]
    let data = Data((lines.joined(separator: "\n") + "\n").utf8)
    try data.write(to: sessionURL)

    let checkpoint = SourceCheckpoint(
      threadID: threadID,
      path: sessionURL.path,
      inode: 1,
      modifiedAt: Date()
    )
    let parsed = try parser.parse(
      url: sessionURL,
      checkpoint: checkpoint,
      maximumOffset: UInt64(data.count)
    )

    XCTAssertEqual(parsed.byteOffset, UInt64(data.count))
    let task = try XCTUnwrap(database.task(id: turnID))
    XCTAssertEqual(task.title, "Build a usage dashboard")
    XCTAssertEqual(task.project, "sample-workspace")
    XCTAssertEqual(task.status, .completed)
    XCTAssertEqual(task.inputTokens, 100)
    XCTAssertEqual(task.outputTokens, 20)
    XCTAssertEqual(task.totalTokens, 120)

    let usage = try database.usage(start: .distantPast, end: .distantFuture)
    XCTAssertEqual(usage.inputTokens, 100)
    XCTAssertEqual(usage.outputTokens, 20)
    XCTAssertEqual(usage.totalTokens, 120)
  }
}
