import SwiftUI

/// 开关：开是黑色，关是灰色，白色滑块。
struct BentoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoSwitch(configuration: configuration)
    }
}

private struct BentoSwitch: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = BentoMetric.toggleSize
        let knob = size.height - BentoSpace.s4
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? BentoColor.Ink.black : BentoColor.Status.idle)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(BentoColor.Bg.surface)
                        .frame(width: knob, height: knob)
                        .padding(BentoSpace.s2)
                }
                .contentShape(Capsule())
                // 跟着值动：操作失败回滚时滑块也会滑回去
                .animation(reduceMotion ? nil : BentoMotion.snappy, value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : BentoOpacity.dimmed)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// 勾选框：一个圆角方块 + 右边的内容，整行可点。
struct BentoCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BentoCheckbox(configuration: configuration)
    }
}

private struct BentoCheckbox: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: BentoSpace.s10) {
                box
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : BentoOpacity.dimmed)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: BentoRadius.xs, style: .continuous)
        return shape
            .fill(configuration.isOn ? BentoColor.Ink.black : BentoColor.Bg.surface)
            .overlay(shape.strokeBorder(BentoColor.Ink.tertiary, lineWidth: BentoMetric.selectionStroke)
                .opacity(configuration.isOn ? 0 : 1))
            .overlay {
                BentoIcon.check.image
                    .font(.system(size: BentoMetric.iconSizeSmall, weight: .bold))
                    .foregroundStyle(BentoColor.Ink.inverse)
                    .scaleEffect(configuration.isOn ? 1 : 0.4)
                    .opacity(configuration.isOn ? 1 : 0)
            }
            .frame(width: BentoMetric.checkbox, height: BentoMetric.checkbox)
            .animation(BentoMotion.hover, value: configuration.isOn)
    }
}

extension ToggleStyle where Self == BentoToggleStyle {
    static var bento: BentoToggleStyle { BentoToggleStyle() }
}

extension ToggleStyle where Self == BentoCheckboxStyle {
    static var bentoCheckbox: BentoCheckboxStyle { BentoCheckboxStyle() }
}
