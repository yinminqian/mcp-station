import SwiftUI

/// 设置：系统设置式分组表单。主题切换即时生效，停留在当前页。
struct GlassSettingsPage: View {
    @Environment(AppStore.self) private var store
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .glass

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ForEach(AppTheme.allCases) { t in
                        ThemeTile(theme: t, selected: theme == t) { theme = t }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("外观")
            } footer: {
                Text("两套界面共用同一份数据，切换后停留在当前页面。")
            }

            Section {
                LabeledContent("配置文件") {
                    Text(ConfigStore.url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("导入…") { ConfigTransfer.importFromFile(store: store) }
                        .disabled(store.isBusy("import") || !(store.core?.canManage ?? false))
                    Button("导出…") { ConfigTransfer.exportToFile(store: store) }
                        .disabled(!(store.core?.canManage ?? false))
                    Spacer()
                    Button("在访达中显示") { ConfigTransfer.revealConfigFile() }
                }
            } header: {
                Text("配置")
            } footer: {
                Text("导入认本软件导出的文件，也认 Claude Code、Claude Desktop、Cursor、VS Code 等带 mcpServers 的 JSON；同名的 MCP 会被覆盖。导出的文件里有密钥明文。")
            }

            Section {
                GlassPortRow(port: store.core?.port ?? ConfigFile.defaultPort)
                LabeledContent("状态") {
                    if let core = store.core {
                        switch core.state {
                        case .running: Text("运行中")
                        case .notInstalled: Text("还没接入").foregroundStyle(.secondary)
                        case .restarting: Text("重启中…")
                        case .stopped: Text("没有运行").foregroundStyle(.red)
                        }
                    }
                }
                LabeledContent("重新读取配置并检测所有 MCP") {
                    Button("重新检测") { store.restartCore() }
                        .disabled(store.isBusy("core-restart"))
                }
            } header: {
                Text("网关")
            } footer: {
                Text("客户端连的是网关地址。网关还没接入时，MCP 由 App 启动并常驻，能检测、试调用、看内存；客户端还连不上，所以调用记录里只有试调用。")
            }

            Section {
                Toggle("登录时打开 MCP Station", isOn: .constant(false)).disabled(true)
            } header: {
                Text("启动")
            } footer: {
                Text("网关接入后开放。")
            }

            Section("关于") {
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")
                LabeledContent("有新版时会提示，也可以手动检查") {
                    Button("检查更新…") { Updates.checkNow() }
                        .disabled(!Updates.available)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}

/// 主题选择卡片：一张示意缩略图 + 名称。
private struct ThemeTile: View {
    var theme: AppTheme
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 180, height: 112)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(hovering ? 0.5 : 0.25),
                                      lineWidth: selected ? 3 : 1))
                    .scaleEffect(hovering && !selected ? 1.02 : 1)
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(theme.title).font(.callout.weight(.medium))
                        Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.snappy, value: selected)
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .glass:
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(white: 0.82), Color(white: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.55)).frame(width: 46).padding(5)
                    VStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 1 ? Color.accentColor : .white.opacity(i.isMultiple(of: 2) ? 0.9 : 0.75))
                                .frame(height: 8)
                        }
                    }
                    .padding(.vertical, 18).padding(.trailing, 8)
                }
            }
        case .bento:
            ZStack(alignment: .topLeading) {
                Color(red: 0.984, green: 0.976, blue: 0.965)
                HStack(alignment: .top, spacing: 6) {
                    Capsule().fill(Color(red: 0.95, green: 0.94, blue: 0.92)).frame(width: 14).padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.75)).frame(width: 70, height: 9)
                        HStack(spacing: 5) {
                            tile(.init(red: 0.976, green: 0.867, blue: 0.741))
                            tile(.init(red: 0.851, green: 0.824, blue: 0.976))
                        }
                        HStack(spacing: 5) {
                            tile(.init(red: 0.761, green: 0.925, blue: 0.847))
                            tile(.init(red: 0.804, green: 0.894, blue: 0.965))
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(6)
            }
        }
    }

    private func tile(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(c).frame(width: 58, height: 32)
    }
}

/// 网关端口：回车保存进配置；被别的程序占着时在下面提示一句。
private struct GlassPortRow: View {
    let port: Int

    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var occupiedBy: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(verbatim: "127.0.0.1:").foregroundStyle(.secondary)
                TextField("端口", text: $text)
                    .labelsHidden()
                    .frame(width: 70)
                    .onSubmit(save)
            }
            .monospacedDigit()
        } label: {
            Text("端口")
            if let occupiedBy {
                Text("\(String(port)) 已经被 \(occupiedBy) 占着，网关接入后会起不来，建议换一个")
                    .foregroundStyle(.orange)
            } else {
                Text("回车保存")
            }
        }
        .task(id: port) {
            text = String(port)
            occupiedBy = await PortCheck.listener(on: port)
        }
    }

    private func save() {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else {
            store.showToast("端口要填数字", style: .error)
            text = String(port)
            return
        }
        guard n != port else { return }
        Task { if !(await store.setPort(n)) { text = String(port) } }
    }
}
