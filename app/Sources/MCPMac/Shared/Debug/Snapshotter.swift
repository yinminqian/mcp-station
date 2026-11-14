import AppKit
import os
import SwiftUI

/// 调试用：带环境变量 `MCPMAC_SNAPSHOT_DIR=<目录>` 启动时，依次切换两套主题 × 每个页面
/// （再加"后台服务没运行"场景），把主窗口和菜单栏面板渲染成 PNG，然后退出。
///
/// 用 `cacheDisplay` 渲染，不需要屏幕录制权限；代价是系统的毛玻璃材质可能画不出来，
/// 所以它只用来核对布局、文字、裁切，质感仍要人眼看。
@MainActor
enum Snapshotter {
    static var outputDir: URL? {
        ProcessInfo.processInfo.environment["MCPMAC_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested(store: AppStore, nav: Navigator, copy: CopyFeedback) {
        guard let dir = outputDir else { return }
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // 只改本 App 的外观，不碰系统设置
            if ProcessInfo.processInfo.environment["MCPMAC_SNAPSHOT_APPEARANCE"] == "dark" {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            try? await Task.sleep(for: .seconds(1.5))
            let only = ProcessInfo.processInfo.environment["MCPMAC_SNAPSHOT_THEME"]
            for theme in AppTheme.allCases where only == nil || only == theme.rawValue {
                UserDefaults.standard.set(theme.rawValue, forKey: AppTheme.storageKey)
                for route in Navigator.Route.allCases {
                    nav.route = route
                    try? await Task.sleep(for: .milliseconds(900))
                    capture(name: "\(theme.rawValue)-\(route.rawValue)", to: dir)
                }
                renderMenuPanel(theme: theme, store: store, nav: nav, copy: copy, to: dir)
            }
            NSApp.terminate(nil)
        }
    }

    /// 调试：`MCPMAC_START_ROUTE=<overview|mcps|services|calls|settings>` 以指定页面启动（性能测量用）。
    static func applyStartRoute(nav: Navigator) {
        if let r = ProcessInfo.processInfo.environment["MCPMAC_START_ROUTE"].flatMap(Navigator.Route.init(rawValue:)) {
            nav.route = r
        }
    }

    /// 调试：切页基准测试（性能验收用，见 docs/perf/）。
    ///
    /// - `MCPMAC_SWITCH_BENCH=1` 开启；启动 4 秒后按 `Navigator.Route` 顺序轮流切页，每次间隔 0.5 秒。
    /// - `MCPMAC_SWITCH_COUNT=<n>` 切页次数，默认 16（SwiftUI 泳道只能录约 10 秒，录它时用 8）。
    /// - `MCPMAC_SWITCH_MODE=natural|forced`，默认 natural：
    ///   - natural：只设置 `nav.route`，计时到主线程下一次进入空闲（runloop beforeWaiting），
    ///     包含布局、绘制和 Core Animation 提交，即用户实际感受到的阻塞；
    ///   - forced：设置后同步 `layoutSubtreeIfNeeded()` + `displayIfNeeded()` 再停表（与 2026-11-14 基线版本相同，用于对比）。
    /// - 每次切页包一对 os_signpost 区间（subsystem `com.example.mcp-mac`，category PointsOfInterest，name `switch`）。
    /// - `MCPMAC_SWITCH_ROUTES=a,b,...` 指定切页序列（循环）；`MCPMAC_SWITCH_DWELL_MS=<ms>` 每次切页后停留多久（默认 500）。
    /// - `MCPMAC_SWITCH_STAY=<route>`（或 1 = overview）切完不退出、停在该页（测访问过所有页面后的空闲 CPU）。
    /// - 首次进入与再次进入分开打印；找不到可见窗口时报错退出（退出码 2），不再静默打印 0。
    static func runSwitchBenchIfRequested(nav: Navigator) {
        let env = ProcessInfo.processInfo.environment
        guard env["MCPMAC_SWITCH_BENCH"] == "1" else { return }
        let count = env["MCPMAC_SWITCH_COUNT"].flatMap(Int.init) ?? 16
        let dwell = env["MCPMAC_SWITCH_DWELL_MS"].flatMap(Int.init) ?? 500
        // 指定切页序列（逗号分隔，循环使用），例如 calls,overview 或 overview,settings
        let sequence = env["MCPMAC_SWITCH_ROUTES"].map { $0.split(separator: ",").compactMap { Navigator.Route(rawValue: String($0)) } }
        let forced = env["MCPMAC_SWITCH_MODE"] == "forced"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else {
                FileHandle.standardError.write("bench error: 没有可见的主窗口\n".data(using: .utf8)!)
                exit(2)
            }
            // 先激活到前台：窗口不在屏幕上时 AppKit 会多做 50～75ms 软件光栅化，轮与轮之间不可比（REPORT-02 §5）
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            let occluded = !window.occlusionState.contains(.visible)
            FileHandle.standardError.write("bench window onScreen=\(window.isOnActiveSpace && window.isVisible) occluded=\(occluded)\n".data(using: .utf8)!)
            // 窗口被遮住时 SwiftUI 不做布局和绘制，natural 模式量不到东西（会全是 0），直接报错
            if occluded && !forced {
                FileHandle.standardError.write("bench error: 窗口被遮挡，natural 模式无法测量（请让窗口在当前桌面可见，或用 MCPMAC_SWITCH_MODE=forced）\n".data(using: .utf8)!)
                exit(3)
            }
            let root = window.contentView?.superview ?? window.contentView
            let signposter = OSSignposter(subsystem: "com.example.mcp-mac", category: .pointsOfInterest)
            var visited: Set<String> = [nav.route.rawValue]
            var first: [String: Double] = [:]
            var again: [String: [Double]] = [:]
            let routes = Navigator.Route.allCases
            let start = routes.firstIndex(of: nav.route) ?? 0
            for i in 1...count {
                let r: Navigator.Route
                if let seq = sequence, !seq.isEmpty { r = seq[(i - 1) % seq.count] } else { r = routes[(start + i) % routes.count] }
                let state = signposter.beginInterval("switch", id: signposter.makeSignpostID(), "\(r.rawValue, privacy: .public)")
                let t0 = CACurrentMediaTime()
                nav.route = r
                if forced {
                    root?.layoutSubtreeIfNeeded()
                    root?.displayIfNeeded()
                }
                let ms = forced ? (CACurrentMediaTime() - t0) * 1000 : (await mainThreadSettled() - t0) * 1000
                signposter.endInterval("switch", state)
                if visited.insert(r.rawValue).inserted { first[r.rawValue] = ms } else { again[r.rawValue, default: []].append(ms) }
                try? await Task.sleep(for: .milliseconds(dwell))
            }
            let mode = forced ? "forced" : "natural"
            for r in routes.map(\.rawValue) {
                let f = first[r].map { String(format: "%.0f", $0) } ?? "-"
                let a = (again[r] ?? []).map { String(format: "%.0f", $0) }.joined(separator: " ")
                FileHandle.standardError.write("bench[\(mode)] \(r): first \(f) | again \(a) ms\n".data(using: .utf8)!)
            }
            // MCPMAC_SWITCH_STAY=1：切完不退出、停在概览页，用来测"所有页面都访问过之后"的空闲 CPU
            if let stay = env["MCPMAC_SWITCH_STAY"] {
                nav.route = Navigator.Route(rawValue: stay) ?? .overview
                FileHandle.standardError.write("bench done, staying\n".data(using: .utf8)!)
                return
            }
            NSApp.terminate(nil)
        }
    }

    /// 等到主线程"安定"：连续空闲超过 10ms 才算切页结束，返回最后一段工作结束的时刻。
    ///
    /// 只等第一次空闲会提前停表：切页的工作有时分成两段，中间主线程会空闲 1～2ms（REPORT-02 §4）。
    /// 不足 1ms 的唤醒（比如这里的轮询定时器）不算工作。
    private static func mainThreadSettled(quiet: Double = 0.010) async -> CFTimeInterval {
        /// 只在主线程 runloop 的回调里读写（观察者和定时器都挂在主 runloop 上）。
        final class State: @unchecked Sendable {
            var wokeAt = CACurrentMediaTime()
            var lastWorkEnd = CACurrentMediaTime()
            var done = false
            var observer: CFRunLoopObserver?
        }
        let st = State()
        return await withCheckedContinuation { (c: CheckedContinuation<CFTimeInterval, Never>) in
            let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
            st.observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Int.max) { _, act in
                let now = CACurrentMediaTime()
                if act == .afterWaiting { st.wokeAt = now }
                else if now - st.wokeAt > 0.001 { st.lastWorkEnd = now }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), st.observer, .commonModes)
            let timer = Timer(timeInterval: 0.002, repeats: true) { t in
                guard !st.done, CACurrentMediaTime() - st.lastWorkEnd >= quiet else { return }
                st.done = true
                t.invalidate()
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), st.observer, .commonModes)
                c.resume(returning: st.lastWorkEnd)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// 调试：`MCPMAC_TRY_CALL="<MCP> <工具> <参数 JSON>"` 启动后等这个 MCP 检测完，自动试调用一次（会记进调用记录）。
    /// 设了 `MCPMAC_TRY_CALL_OUT=<文件>` 时把结果概要（成败、耗时、字数，不含返回内容）写进去。
    static func runTryCallIfRequested(store: AppStore) {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["MCPMAC_TRY_CALL"] else { return }
        let parts = spec.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        Task { @MainActor in
            for _ in 0..<60 {
                if let m = store.mcp(parts[0]), m.state != .starting, m.state != .stopped { break }
                try? await Task.sleep(for: .seconds(1))
            }
            let r = await store.callTool(mcp: parts[0], tool: parts[1], argumentsJSON: parts.count > 2 ? parts[2] : "{}")
            if let out = env["MCPMAC_TRY_CALL_OUT"] {
                let line = r.map { "isError=\($0.isError) duration=\($0.duration) chars=\($0.text.count)\n" } ?? "nil\n"
                try? line.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
    }

    /// 调试：`MCPMAC_CLOSE_TEST=1` 时 2 秒后关闭主窗口，用来验证关窗不会退出进程。
    static func runCloseTestIfRequested() {
        guard ProcessInfo.processInfo.environment["MCPMAC_CLOSE_TEST"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for w in NSApp.windows where w.isVisible && w.canBecomeMain { w.performClose(nil) }
        }
    }

    private static func capture(name: String, to dir: URL) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true || $0.title == "MCP Mac" }),
              let view = window.contentView?.superview ?? window.contentView else { return }
        write(view: view, to: dir.appendingPathComponent("\(name).png"))
    }

    private static func renderMenuPanel(theme: AppTheme, store: AppStore, nav: Navigator, copy: CopyFeedback, to dir: URL) {
        let host = NSHostingView(rootView: MenuBarPanel()
            .environment(store).environment(nav).environment(copy))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: NSSize(width: max(size.width, 360), height: max(size.height, 200)))
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        write(view: host, to: dir.appendingPathComponent("\(theme.rawValue)-menubar.png"))
    }

    private static func write(view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
