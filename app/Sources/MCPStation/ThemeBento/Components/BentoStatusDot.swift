import SwiftUI

/// 界面上的状态语义。颜色只有这几种，MCP 状态和后台服务状态都先映射到它。
enum BentoStatus: Hashable, Sendable {
    case ok, warn, error, idle
    /// 进行中（启动中、重启中）：用提醒色并缓慢闪动。
    case busy

    var color: Color {
        switch self {
        case .ok: BentoColor.Status.green
        case .warn, .busy: BentoColor.Status.peach
        case .error: BentoColor.Status.rose
        case .idle: BentoColor.Status.idle
        }
    }

    /// 状态药丸用的色调。
    var tone: BentoTone {
        switch self {
        case .ok: .mint
        case .warn, .busy: .peach
        case .error: .rose
        case .idle: .sunken
        }
    }
}

extension MCPState {
    var bentoStatus: BentoStatus {
        switch self {
        case .ready: .ok
        case .starting: .busy
        case .backoff: .warn
        case .configError: .error
        case .stopped: .idle
        }
    }
}

extension BentoStatus {
    init(core: CoreStatus?) {
        switch core?.state {
        case .running: self = .ok
        case .notInstalled: self = .idle
        case .restarting: self = .busy
        case .stopped: self = .error
        case nil: self = .idle
        }
    }
}

struct BentoStatusDot: View {
    var status: BentoStatus
    var size: CGFloat = BentoMetric.statusDot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .phaseAnimator(status == .busy && !reduceMotion ? [1.0, 0.3] : [1.0]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.7) }
            .animation(BentoMotion.snappy, value: status)
            .accessibilityHidden(true)
    }
}
