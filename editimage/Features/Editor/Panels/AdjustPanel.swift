//
//  AdjustPanel.swift
//  editimage
//
//  Panel chỉnh Light & Color.
//

import SwiftUI

struct AdjustPanel: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                group("Ánh sáng") {
                    row("Phơi sáng", model.exposure, -2...2, 0)
                    row("Độ sáng", model.brightness, -0.3...0.3, 0)
                    row("Tương phản", model.contrast, 0.5...1.5, 1)
                    row("Vùng sáng", model.highlights, -1...1, 0)
                    row("Vùng tối", model.shadows, -1...1, 0)
                }
                group("Màu sắc") {
                    row("Nhiệt độ", model.temperature, -1...1, 0)
                    row("Sắc thái", model.tint, -1...1, 0)
                    row("Bão hoà", model.saturation, 0...2, 1)
                    row("Rực rỡ", model.vibrance, -1...1, 0)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            content()
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ def: Double) -> some View {
        SliderRow(title: title, value: value, range: range, defaultValue: def, onCommit: model.commitHistory)
    }
}

struct EffectsPanel: View {
    @Bindable var model: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                SliderRow(title: "Nét (Sharpen)", value: model.sharpness, range: 0...2, defaultValue: 0, onCommit: model.commitHistory)
                SliderRow(title: "Chi tiết (Clarity)", value: model.clarity, range: -1...1, defaultValue: 0, onCommit: model.commitHistory)
                SliderRow(title: "Tối góc (Vignette)", value: model.vignette, range: 0...1, defaultValue: 0, onCommit: model.commitHistory)
                SliderRow(title: "Nhiễu film (Grain)", value: model.grain, range: 0...1, defaultValue: 0, onCommit: model.commitHistory)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
