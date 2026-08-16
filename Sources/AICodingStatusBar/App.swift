import AppKit
import SwiftUI

@MainActor
final class DashboardModel: ObservableObject {
  static let shared = DashboardModel()
  @Published var snapshot = DashboardSnapshot.empty
  @Published var indexing = true
  private let collector: CodexCollector?
  private var started = false
  private init() { collector = try? CodexCollector() }
  func start() {
    guard !started else { return }
    started = true
    guard let collector else {
      snapshot.collectorError = "Collector could not start"
      return
    }
    Task {
      while !Task.isCancelled {
        snapshot = await collector.refresh()
        indexing = false
        try? await Task.sleep(for: .seconds(2))
      }
    }
    Task {
      snapshot = await collector.refreshAccount()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15 * 60))
        snapshot = await collector.refreshAccount()
      }
    }
  }
  func refresh() {
    guard let collector else { return }
    Task { snapshot = await collector.refresh() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    DashboardModel.shared.start()
    DashboardWindow.shared.show()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    DashboardWindow.shared.show()
    return true
  }
}

@main
struct AICodingStatusBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject var model = DashboardModel.shared
  var body: some Scene {
    MenuBarExtra {
      DashboardView(model: model, menuMode: true)
    } label: {
      Label(
        "AI Coding",
        systemImage: model.snapshot.runningTasks.isEmpty ? "circle.grid.2x2" : "circle.fill")
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class DashboardWindow: NSObject, NSWindowDelegate {
  static let shared = DashboardWindow()
  private var window: NSWindow?

  private override init() {
    super.init()
  }

  func show() {
    NSApp.setActivationPolicy(.regular)
    if window == nil {
      let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 410, height: 690),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      w.title = "AI Coding"
      w.titleVisibility = .hidden
      w.titlebarAppearsTransparent = true
      w.level = .normal
      w.isMovableByWindowBackground = true
      w.isReleasedWhenClosed = false
      w.minSize = NSSize(width: 390, height: 620)
      w.delegate = self
      w.contentViewController = NSHostingController(
        rootView: DashboardView(model: .shared, menuMode: false))
      w.center()
      window = w
    }
    if window?.isMiniaturized == true { window?.deminiaturize(nil) }
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func collapseToMenuBar() {
    if window?.isMiniaturized == true {
      window?.deminiaturize(nil)
    }
    window?.orderOut(nil)
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    collapseToMenuBar()
    return false
  }
}
