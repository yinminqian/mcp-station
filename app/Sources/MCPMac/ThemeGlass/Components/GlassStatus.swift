import SwiftUI

/// 状态点：正常绿、警告橙、错误红、停止灰。系统色，跟随深浅色。
struct GlassStatusDot: View {
    var state: MCPState
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .ready: .green
        case .starting: .yellow
        case .backoff: .orange
        case .configError: .red
        case .stopped: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

/// "等待重试 · 40s" 这类带倒计时的状态文字。
/// 倒计时只在这个小视图里每秒刷新（TimelineView），不会带动整张表重绘。
struct GlassStateText: View {
    var state: MCPState
    var showsCountdown = true

    var body: some View {
        switch state {
        case .backoff(_, let retryAt, _) where showsCountdown:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(retryAt.timeIntervalSince(ctx.date).rounded(.up)))
                Text(left > 0 ? "等待重试 · \(left)s" : "正在重试…")
                    .monospacedDigit()
                    
            }
        default:
            Text(Format.stateLabel(state))
        }
    }
}

/// 只读的复制按钮：点了图标变对勾。
struct GlassCopyButton: View {
    var text: String
    var key: String
    var label = "复制"
    @Environment(CopyFeedback.self) private var copy

    var body: some View {
        Button {
            copy.copy(text, key: key)
        } label: {
            Image(systemName: copy.isCopied(key) ? "checkmark" : "document.on.document")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(copy.isCopied(key) ? Color.green : Color.secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// stderr / core.log 这类日志块。等宽字体，error/backoff 关键字着色。
struct GlassLogView: View {
    var lines: [LogLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.time(line.time)).foregroundStyle(.tertiary)
                    Text(line.text).foregroundStyle(color(line.level))
                        .textSelection(.enabled)
                }
            }
            if lines.isEmpty {
                Text("还没有日志").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ l: LogLine.Level) -> Color {
        switch l {
        case .info: .primary
        case .warn: .orange
        case .error: .red
        }
    }
}
