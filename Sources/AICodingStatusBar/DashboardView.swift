import AppKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: DashboardModel
  var menuMode: Bool

  var body: some View {
    VStack(spacing: 14) {
      header
      metrics
      activeTasks
      usage
      recentTasks
      footer
    }
    .padding(16)
    .frame(width: 390)
    .frame(minHeight: 610)
    .background(
      LinearGradient(
        colors: [Color(nsColor: .windowBackgroundColor), .black.opacity(0.78)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("AI CODING")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .tracking(1.5)
          .foregroundStyle(.secondary)
        Text("Control Center")
          .font(.system(size: 21, weight: .semibold, design: .rounded))
      }
      Spacer()
      if menuMode {
        Button(action: { DashboardWindow.shared.show() }) {
          Image(systemName: "macwindow.on.rectangle")
        }
        .buttonStyle(.plain)
        .help("Open dashboard window")
      } else {
        Button(action: { DashboardWindow.shared.collapseToMenuBar() }) {
          Image(systemName: "menubar.rectangle")
        }
        .buttonStyle(.plain)
        .help("Collapse to menu bar")
      }
      Button(action: { model.refresh() }) {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .help("Refresh local data")
    }
  }

  private var metrics: some View {
    HStack(spacing: 8) {
      Metric(label: "Running", value: model.snapshot.runningTasks.count, color: .green)
      Metric(label: "Completed", value: model.snapshot.completedToday, color: .secondary)
      Metric(label: "Failed", value: model.snapshot.failedToday, color: .red)
    }
  }

  private var activeTasks: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle("ACTIVE TASKS · ALL PROJECTS")
      if model.snapshot.runningTasks.isEmpty {
        HStack(spacing: 10) {
          Circle()
            .fill(.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
          VStack(alignment: .leading) {
            Text(model.indexing ? "Indexing all Codex sessions…" : "No Codex task is running")
              .font(.system(size: 14, weight: .medium))
            Text("ChatGPT + Codex")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .card()
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(model.snapshot.runningTasks) { task in
              ActiveCard(task: task)
            }
          }
        }
        .frame(maxHeight: min(CGFloat(model.snapshot.runningTasks.count) * 108, 250))
      }
    }
  }

  private var usage: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle("USAGE · THIS MAC")
      VStack(spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Text(TokenText.compact(model.snapshot.todayUsage.totalTokens))
              .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Tokens").font(.caption2).foregroundStyle(.tertiary)
          }
          Spacer()
          Breakdown(label: "Input", value: model.snapshot.todayUsage.inputTokens)
          Breakdown(label: "Output", value: model.snapshot.todayUsage.outputTokens)
        }
        Divider().opacity(0.45)
        if let weekly = model.snapshot.weeklyLimit, weekly.isWeekly {
          VStack(spacing: 7) {
            HStack {
              Text("Weekly Remaining").font(.caption).foregroundStyle(.secondary)
              Spacer()
              Text("\(Int(weekly.remainingPercent.rounded()))%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            ProgressView(value: weekly.remainingPercent, total: 100)
              .tint(weekly.remainingPercent < 15 ? .red : .green)
            HStack {
              Text("Reset")
              Spacer()
              Text(weekly.resetsAt, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
          }
        } else {
          HStack {
            Text("Weekly Remaining")
            Spacer()
            Text("Unavailable")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .card()
    }
  }

  private var recentTasks: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle("RECENT CONVERSATIONS · ALL PROJECTS")
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(
            Array(model.snapshot.recentConversations.prefix(8).enumerated()), id: \.element.id
          ) { index, task in
            ConversationRow(task: task)
            if index < min(8, model.snapshot.recentConversations.count) - 1 {
              Divider().padding(.leading, 22).opacity(0.35)
            }
          }
        }
      }
      .frame(maxHeight: 190)
      .card(horizontal: 10, vertical: 4)
    }
  }

  private var footer: some View {
    VStack(spacing: 4) {
      if let error = model.snapshot.collectorError {
        Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
      }
      HStack {
        Label("Codex", systemImage: "terminal")
        Spacer()
        Text("Updated \(model.snapshot.lastUpdatedAt, style: .relative)")
        if menuMode {
          Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
        }
      }
      .font(.caption2)
      .foregroundStyle(.tertiary)
    }
  }
}

private struct Metric: View {
  var label: String
  var value: Int
  var color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 6, height: 6)
        Text("\(value)").font(.system(size: 17, weight: .semibold, design: .rounded))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(horizontal: 10, vertical: 9)
  }
}

private struct ActiveCard: View {
  var task: CodingTask

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(alignment: .top, spacing: 10) {
        Circle()
          .fill(.green)
          .frame(width: 9, height: 9)
          .shadow(color: .green.opacity(0.55), radius: 4)
          .padding(.top, 5)
        VStack(alignment: .leading, spacing: 5) {
          Text(task.project).font(.caption).foregroundStyle(.secondary)
          Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
          HStack(spacing: 8) {
            Text(task.isPrimary ? "Codex" : "Subagent")
            Text(DurationText.compact(from: task.startedAt, to: context.date))
            Text("Active \(task.lastActivityAt, style: .relative)")
          }
          .font(.caption2)
          .foregroundStyle(.tertiary)
        }
        Spacer()
        Text(TokenText.compact(task.totalTokens))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .card()
    }
  }
}

private struct Breakdown: View {
  var label: String
  var value: Int64

  var body: some View {
    VStack(alignment: .trailing, spacing: 3) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(TokenText.compact(value)).font(.system(size: 13, weight: .medium, design: .rounded))
    }
    .frame(minWidth: 66, alignment: .trailing)
  }
}

private struct ConversationRow: View {
  var task: CodingTask

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: icon).foregroundStyle(color).frame(width: 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(task.title).font(.caption.weight(.medium)).lineLimit(1)
        Text("\(task.project) · \(TokenText.compact(task.totalTokens)) · \(duration)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer()
      if task.status == .running {
        Text("Running").font(.caption2.weight(.medium)).foregroundStyle(.green)
      } else if let completedAt = task.completedAt {
        Text(completedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 7)
  }

  private var icon: String {
    switch task.status {
    case .running: return "circle.fill"
    case .completed: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    case .interrupted: return "stop.circle.fill"
    case .unknown: return "questionmark.circle.fill"
    }
  }

  private var color: Color {
    switch task.status {
    case .running: return .green
    case .completed, .unknown: return .secondary
    case .failed: return .red
    case .interrupted: return .orange
    }
  }

  private var duration: String {
    if let milliseconds = task.durationMilliseconds {
      return DurationText.compact(seconds: Double(milliseconds) / 1000)
    }
    return DurationText.compact(from: task.startedAt, to: task.lastActivityAt)
  }
}

private struct SectionTitle: View {
  var text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .semibold, design: .rounded))
      .tracking(1.2)
      .foregroundStyle(.tertiary)
  }
}

private enum TokenText {
  static func compact(_ value: Int64) -> String {
    let number = Double(value)
    if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
  }
}

private enum DurationText {
  static func compact(from: Date, to: Date) -> String {
    compact(seconds: max(0, to.timeIntervalSince(from)))
  }

  static func compact(seconds: TimeInterval) -> String {
    let seconds = Int(seconds)
    if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
    if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
    return "\(seconds)s"
  }
}

extension View {
  fileprivate func card(horizontal: CGFloat = 12, vertical: CGFloat = 11) -> some View {
    padding(.horizontal, horizontal)
      .padding(.vertical, vertical)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.white.opacity(0.055))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.white.opacity(0.065), lineWidth: 1)
          )
      )
  }
}
