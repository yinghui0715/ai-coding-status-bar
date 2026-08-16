import Foundation

struct CodexEnvironment: Sendable {
  let userHome: URL
  let dataHome: URL
  let executableURL: URL?
  let projectStateURLs: [URL]

  var sessionRoots: [URL] {
    [
      dataHome.appendingPathComponent("sessions", isDirectory: true),
      dataHome.appendingPathComponent("archived_sessions", isDirectory: true),
    ]
  }

  static func discover(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> CodexEnvironment {
    let dataHome = resolveDataHome(environment: environment, userHome: userHome)
    let executableURL = resolveExecutable(
      environment: environment,
      userHome: userHome,
      fileManager: fileManager
    )
    let stateURLs = unique([
      userHome.appendingPathComponent(".codex-global-state.json"),
      dataHome.appendingPathComponent(".codex-global-state.json"),
    ])
    return CodexEnvironment(
      userHome: userHome,
      dataHome: dataHome,
      executableURL: executableURL,
      projectStateURLs: stateURLs
    )
  }

  static func resolveDataHome(environment: [String: String], userHome: URL) -> URL {
    for key in ["AI_CODING_CODEX_HOME", "CODEX_HOME"] {
      if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
      {
        return url(raw, userHome: userHome)
      }
    }
    return userHome.appendingPathComponent(".codex", isDirectory: true)
  }

  static func resolveExecutable(
    environment: [String: String],
    userHome: URL,
    fileManager: FileManager
  ) -> URL? {
    var candidates: [URL] = []
    if let override = environment["AI_CODING_CODEX_EXECUTABLE"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      candidates.append(url(override, userHome: userHome))
    }

    candidates.append(
      URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
    )

    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map {
          URL(fileURLWithPath: String($0), isDirectory: true)
            .appendingPathComponent("codex")
        })
    }

    candidates.append(contentsOf: [
      URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
      URL(fileURLWithPath: "/usr/local/bin/codex"),
    ])

    return unique(candidates).first {
      fileManager.isExecutableFile(atPath: $0.path)
    }
  }

  private static func url(_ raw: String, userHome: URL) -> URL {
    if raw == "~" {
      return userHome.standardizedFileURL
    }
    if raw.hasPrefix("~/") {
      return
        userHome
        .appendingPathComponent(String(raw.dropFirst(2)))
        .standardizedFileURL
    }
    if raw.hasPrefix("/") {
      return URL(fileURLWithPath: raw).standardizedFileURL
    }
    return userHome.appendingPathComponent(raw).standardizedFileURL
  }

  private static func unique(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }
}
