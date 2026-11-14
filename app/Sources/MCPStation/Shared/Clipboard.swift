import AppKit
import SwiftUI

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// "复制"的视觉反馈：点完图标变对勾 1.2 秒。两套主题各自决定外观，状态逻辑共用这里。
@MainActor @Observable
final class CopyFeedback {
    private(set) var copiedKey: String?
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    func copy(_ text: String, key: String) {
        Clipboard.copy(text)
        withAnimation(.snappy) { copiedKey = key }
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.copiedKey = nil }
        }
    }

    func isCopied(_ key: String) -> Bool { copiedKey == key }
}
