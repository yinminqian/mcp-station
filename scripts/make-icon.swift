// 从 app/Resources/AppIcon.svg 生成 app/Resources/AppIcon.icns（用系统自带的 SVG 渲染，不需要装别的工具）。
// 用法：swift scripts/make-icon.swift      改了 SVG 后跑一次，把生成的 .icns 一起提交。
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let res = root.appendingPathComponent("app/Resources")
guard let svg = NSImage(contentsOf: res.appendingPathComponent("AppIcon.svg")) else {
    fatalError("读不了 AppIcon.svg")
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

// 顺便出一张 512 的 PNG，给 README 用
let preview = res.appendingPathComponent("AppIcon-512.png")
try? FileManager.default.removeItem(at: preview)
try FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_256x256@2x.png"), to: preview)

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", res.appendingPathComponent("AppIcon.icns").path]
try p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "已生成 app/Resources/AppIcon.icns" : "iconutil 失败")
