import AppKit
import UniformTypeIdentifiers

/// 配置文件的导入、导出、在访达中显示。两套主题和菜单栏命令共用，用系统的打开 / 保存面板。
@MainActor
enum ConfigTransfer {
    static func importFromFile(store: AppStore) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "导入配置")
        panel.message = String(localized: "选择本软件导出的配置，或 Claude Code、Claude Desktop、Cursor、VS Code 等带 mcpServers 的 JSON 文件。同名的 MCP 会被覆盖。")
        panel.prompt = String(localized: "导入")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        // 很多客户端的配置文件是隐藏文件（~/.claude.json、~/.cursor/mcp.json）
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.importConfig(from: url) }
    }

    static func exportToFile(store: AppStore) {
        let panel = NSSavePanel()
        panel.title = String(localized: "导出配置")
        panel.message = String(localized: "导出的文件里有密钥明文，请妥善保存，不要直接发给别人。")
        panel.prompt = String(localized: "导出")
        panel.nameFieldStringValue = "mcp-station-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.exportConfig(to: url) }
    }

    /// 文件已经存在就在访达里选中它，否则打开它所在的目录（第一次保存前还没有这个文件）。
    static func revealConfigFile() {
        let url = ConfigStore.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }
}
