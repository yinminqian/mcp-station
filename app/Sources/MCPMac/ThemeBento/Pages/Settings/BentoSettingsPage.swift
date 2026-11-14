import SwiftUI

/// 设置页：外观、配置文件、网关、关于。
struct BentoSettingsPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: BentoSpace.s12) {
            Text("设置")
                .bentoText(.headline, BentoColor.Ink.black)
                .frame(height: BentoMetric.controlHeight)
                .padding(.leading, BentoSpace.s4)
            BentoPanel {
                ScrollView {
                    // 两行两列，同一行的两张卡片等高、底边对齐（各列自己往下排会参差不齐，2026-11-14 用户反馈"有点乱"）
                    Grid(horizontalSpacing: BentoSpace.s12, verticalSpacing: BentoSpace.s12) {
                        GridRow {
                            BentoAppearanceCard()
                            BentoCoreSettingsCard()
                        }
                        GridRow {
                            BentoConfigCard()
                            BentoAboutCard()
                        }
                    }
                    .padding(BentoSpace.s20)
                }
                .scrollIndicators(.never)
            }
        }
        .bentoPageInsets()
    }
}

/// 设置页里一张卡片的统一外框：小标题 + 内容。
private struct BentoSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        BentoCard {
            VStack(alignment: .leading, spacing: BentoSpace.s12) {
                BentoSectionLabel(title)
                content
            }
            // 拉满这一行的高度，内容顶对齐
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// 外观：两套主题各一张预览卡片。切换立即生效，页面和选中项不变（它们在共享的 Navigator 里）。
private struct BentoAppearanceCard: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .glass

    var body: some View {
        BentoSettingsCard(title: "外观") {
            HStack(spacing: BentoSpace.s12) {
                ForEach(AppTheme.allCases) { option in
                    BentoThemeOption(theme: option, isSelected: option == theme) { theme = option }
                }
            }
        }
    }
}

private struct BentoThemeOption: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BentoCard(tone: .panel, radius: BentoRadius.md, padding: BentoSpace.s10, isSelected: isSelected) {
                VStack(alignment: .leading, spacing: BentoSpace.s10) {
                    BentoThemeThumbnail(theme: theme)
                    HStack(alignment: .top, spacing: BentoSpace.s8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(theme.title).bentoText(.bodyStrong)
                            Text(theme.subtitle).bentoText(.label, BentoColor.Ink.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        BentoIconCircle(icon: .check, size: BentoSpace.s20,
                                        fill: BentoColor.Ink.black, ink: BentoColor.Ink.inverse)
                            .opacity(isSelected ? 1 : 0)
                            .scaleEffect(isSelected ? 1 : 0.5)
                            .animation(BentoMotion.snappy, value: isSelected)
                    }
                    .padding(.horizontal, BentoSpace.s4)
                }
            }
        }
        .buttonStyle(.bentoCard(radius: BentoRadius.md))
        .accessibilityLabel("\(theme.title)，\(theme.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 主题的示意小图：几块色块摆出各自的版式。
private struct BentoThemeThumbnail: View {
    let theme: AppTheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BentoRadius.sm, style: .continuous)
        Group {
            switch theme {
            case .bento: bento
            case .glass: glass
            }
        }
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private func block(_ color: Color, radius: CGFloat = BentoRadius.xs) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
    }

    /// 窄图标栏 + 粉彩卡片 + 右栏。
    private var bento: some View {
        HStack(spacing: BentoSpace.s6) {
            VStack(alignment: .leading, spacing: BentoSpace.s4) {
                block(BentoTone.lavender.fill).frame(height: BentoSpace.s8)
                ForEach(0..<3, id: \.self) { _ in
                    block(BentoColor.Ink.tertiary.opacity(0.4)).frame(width: 18, height: BentoSpace.s6)
                }
                Spacer(minLength: 0)
            }
            .padding(BentoSpace.s4)
            .frame(width: 34)
            .background(BentoColor.Bg.panel, in: RoundedRectangle(cornerRadius: BentoRadius.sm, style: .continuous))
            VStack(spacing: BentoSpace.s4) {
                block(BentoColor.Ink.black).frame(width: 46, height: BentoSpace.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: BentoSpace.s4) {
                    block(BentoTone.peach.fill); block(BentoTone.lavender.fill); block(BentoTone.sky.fill)
                }
                HStack(spacing: BentoSpace.s4) {
                    block(BentoTone.mint.fill); block(BentoTone.lavender.fill); block(BentoTone.mint.fill)
                }
            }
            block(BentoColor.Bg.panel, radius: BentoRadius.sm).frame(width: 44)
        }
        .padding(BentoSpace.s8)
        .background(BentoColor.Bg.window)
    }

    /// 侧边栏 + 列表行。
    private var glass: some View {
        HStack(spacing: 0) {
            VStack(spacing: BentoSpace.s4) {
                ForEach(0..<4, id: \.self) { row in
                    block(row == 1 ? BentoTone.sky.ink : BentoColor.Ink.tertiary).frame(height: BentoSpace.s8)
                }
                Spacer(minLength: 0)
            }
            .padding(BentoSpace.s8)
            .frame(width: 64)
            .background(BentoColor.Bg.sunken)
            VStack(spacing: BentoSpace.s4) {
                ForEach(0..<5, id: \.self) { _ in
                    block(BentoColor.Bg.sunken).frame(height: BentoSpace.s10)
                }
                Spacer(minLength: 0)
            }
            .padding(BentoSpace.s8)
            .background(BentoColor.Bg.surface)
        }
    }
}

/// 后台服务：状态、地址、版本、重启。
private struct BentoCoreSettingsCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let core = store.core
        BentoSettingsCard(title: "网关") {
            VStack(alignment: .leading, spacing: 0) {
                BentoKeyValueRow(key: "状态") {
                    HStack(spacing: BentoSpace.s8) {
                        BentoStatusDot(status: BentoStatus(core: core))
                        Text(core.bentoHeadline).bentoText(.bodyStrong)
                    }
                    .lineLimit(1)
                }
                if let core {
                    BentoPortRow(port: core.port)
                }
                if let core, core.memory != nil {
                    BentoKeyValueRow(key: "内存") {
                        HStack(spacing: BentoSpace.s6) {
                            BentoMemoryText(bytes: core.memory)
                            BentoMemoryText(bytes: store.totalMemory, prefix: "· 连同所有 MCP 合计 ")
                                .foregroundStyle(BentoColor.Ink.secondary)
                        }
                        .bentoText(.body)
                        .lineLimit(1)
                    }
                }
            }
            HStack(spacing: BentoSpace.s10) {
                BentoRestartCoreButton(tone: .ink)
                Text(core?.state == .notInstalled ? "重新读配置，所有 MCP 重新握手" : "重启后客户端需要重新连接")
                    .bentoText(.label, BentoColor.Ink.secondary)
                    .lineLimit(1)
            }
            if core?.state == .notInstalled {
                BentoNote(tag: "说明", text: "网关还没接入：MCP 由 App 启动并常驻，能检测、试调用、看内存；客户端还连不上，所以调用记录里只有试调用。")
            }
        }
    }
}

/// 配置文件：路径、导入、导出、在访达中显示。
private struct BentoConfigCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let canManage = store.core?.canManage ?? false
        BentoSettingsCard(title: "配置") {
            let path = ConfigStore.url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")
            BentoKeyValueRow(key: "配置文件") {
                Text(path)
                    .bentoText(.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            HStack(spacing: BentoSpace.s8) {
                Button("导入…") { ConfigTransfer.importFromFile(store: store) }
                    .buttonStyle(.bento(.ink, size: .small))
                    .disabled(!canManage || store.isBusy("import"))
                Button("导出…") { ConfigTransfer.exportToFile(store: store) }
                    .buttonStyle(.bento(.panel, size: .small))
                    .disabled(!canManage)
                Button {
                    ConfigTransfer.revealConfigFile()
                } label: {
                    Label("在访达中显示", bento: .folder)
                }
                .buttonStyle(.bento(.panel, size: .small))
            }
            BentoNote(tag: "说明", text: "导入支持本软件导出的文件和 Claude Code、Cursor 等的 mcpServers 配置，同名会覆盖；导出的文件含密钥明文。")
        }
    }
}

/// 关于。
private struct BentoAboutCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        BentoSettingsCard(title: "关于") {
            HStack(spacing: BentoSpace.s12) {
                BentoIconCircle(icon: .brand, size: BentoMetric.railButton,
                                fill: BentoColor.Ink.black, ink: BentoColor.Ink.inverse)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MCP Mac").bentoText(.title)
                    Text("本机 MCP 网关：一个地址，背后有哪些 MCP 由开关和服务决定")
                        .bentoText(.label, BentoColor.Ink.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                BentoKeyValueRow("App 版本", appVersion ?? "开发版")
                BentoKeyValueRow("MCP", "\(store.mcps.count) 个，\(store.mcps.reduce(0) { $0 + $1.toolCount }) 个工具")
            }
        }
    }
}

/// 网关端口：直接改，回车或点「保存」写进配置。顺便看一眼这个端口是不是被别的程序占着。
private struct BentoPortRow: View {
    let port: Int

    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var occupiedBy: String?

    var body: some View {
        let dirty = text.trimmingCharacters(in: .whitespaces) != String(port)
        BentoKeyValueRow(key: "端口") {
            VStack(alignment: .leading, spacing: BentoSpace.s4) {
                HStack(spacing: BentoSpace.s6) {
                    Text("127.0.0.1:").bentoText(.mono, BentoColor.Ink.secondary)
                    TextField("端口", text: $text)
                        .textFieldStyle(.plain)
                        .font(BentoTextStyle.mono.font)
                        .frame(width: BentoSpace.s48 + BentoSpace.s12)
                        .padding(.horizontal, BentoSpace.s10)
                        .frame(height: BentoMetric.controlHeightSmall)
                        .background(BentoColor.Bg.panel, in: Capsule())
                        .onSubmit(save)
                    if dirty {
                        Button("保存", action: save)
                            .buttonStyle(.bento(.ink, size: .small))
                            .disabled(store.isBusy("port"))
                    }
                }
                if let occupiedBy, !dirty {
                    Text("\(String(port)) 已经被 \(occupiedBy) 占着，网关接入后会起不来，建议换一个")
                        .bentoText(.label, BentoTone.peach.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
