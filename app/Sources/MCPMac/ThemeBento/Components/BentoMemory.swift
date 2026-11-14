import SwiftUI

/// 内存数字：「128 MB」。每 5 秒来一次新采样，数字滚动过渡，不闪。
struct BentoMemoryText: View {
    let bytes: Int64?
    var prefix = ""

    var body: some View {
        Text(prefix + Format.bytes(bytes))
            .monospacedDigit()
    }
}

/// 一条小趋势线（内存最近的若干次采样）：一条线加淡淡的面积，没有坐标轴。
struct BentoSparkline: View {
    let values: [Int64]
    var color: Color = BentoColor.Ink.primary

    var body: some View {
        let points = Self.normalize(values)
        BentoSparklineShape(points: points, closed: false)
            .stroke(color, style: StrokeStyle(lineWidth: BentoMetric.selectionStroke, lineCap: .round, lineJoin: .round))
            .background(BentoSparklineShape(points: points, closed: true).fill(color.opacity(BentoOpacity.sparkFill)))
            .accessibilityHidden(true)
    }

    /// 把采样换算成 0…1（0 在下）。波动很小时不放大成锯齿：纵向至少按最大值的 10% 展开。
    private static func normalize(_ values: [Int64]) -> [Double] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let span = max(Double(high - low), Double(high) * 0.1, 1)
        let inset = (span - Double(high - low)) / 2
        return values.map { (Double($0 - low) + inset) / span }
    }
}

private struct BentoSparklineShape: Shape {
    let points: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        // 只有一个采样时画成一条平线
        let ys = points.count == 1 ? [points[0], points[0]] : points
        let step = rect.width / CGFloat(ys.count - 1)
        for (index, value) in ys.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - CGFloat(value) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
