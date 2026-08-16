import Foundation
import XCTest

@testable import AICodingStatusBar

final class CodexEnvironmentTests: XCTestCase {
  func testCustomHomeTakesPriority() {
    let userHome = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let resolved = CodexEnvironment.resolveDataHome(
      environment: [
        "AI_CODING_CODEX_HOME": "~/custom-codex",
        "CODEX_HOME": "/tmp/ignored",
      ],
      userHome: userHome
    )
    XCTAssertEqual(resolved.path, "/Users/example/custom-codex")
  }

  func testCodexHomeFallsBackToDefault() {
    let userHome = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let resolved = CodexEnvironment.resolveDataHome(
      environment: [:],
      userHome: userHome
    )
    XCTAssertEqual(resolved.path, "/Users/example/.codex")
  }

  func testExecutableOverrideIsUsed() {
    let executable = CodexEnvironment.resolveExecutable(
      environment: ["AI_CODING_CODEX_EXECUTABLE": "/bin/sh"],
      userHome: URL(fileURLWithPath: "/Users/example", isDirectory: true),
      fileManager: .default
    )
    XCTAssertEqual(executable?.path, "/bin/sh")
  }

  func testProjectResolverUsesLongestMatchingRoot() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = directory.appendingPathComponent("workspace", isDirectory: true)
    let nested = root.appendingPathComponent("feature", isDirectory: true)
    let stateURL = directory.appendingPathComponent(".codex-global-state.json")
    let object: [String: Any] = [
      "local-projects": [
        "one": ["name": "Workspace", "rootPaths": [root.path]],
        "two": ["name": "Feature", "rootPaths": [nested.path]],
      ]
    ]
    try JSONSerialization.data(withJSONObject: object).write(to: stateURL)

    let resolver = ProjectResolver(stateURLs: [stateURL])
    XCTAssertEqual(
      resolver.name(cwd: nested.appendingPathComponent("Sources").path),
      "Feature"
    )
  }
}
