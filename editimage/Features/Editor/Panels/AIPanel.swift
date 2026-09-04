//
//  AIPanel.swift
//  editimage
//
//  Panel AI offline: tách nền (Vision subject lifting), xoá phông (bokeh),
//  xoá vật thể (brush mask -> inpaint).
//

import SwiftUI

struct AIPanel: View {
    @Bindable var model: EditorViewModel
    /// Yêu cầu EditorView bật chế độ quẹt mask để xoá vật thể.
    let onStartInpaint: () -> Void

    @State private var bokehIntensity: Double = 0.6

    private let bgColors: [(String, String)] = [
        ("Trong suốt", "transparent"),
        ("Trắng", "#FFFFFF"), ("Đen", "#000000"),
        ("Xanh", "#2E7DFF"), ("Hồng", "#FF5D8F"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Tách nền") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(bgColors, id: \.0) { item in
                                ActionChip(title: item.0) {
                                    Task {
                                        let fill: BackgroundFill = item.1 == "transparent"
                                            ? .transparent : .color(hex: item.1)
                                        await model.removeBackground(fill: fill)
                                    }
                                }
                            }
                        }
                    }
                }

                section("Xoá phông (Bokeh)") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Độ mờ").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $bokehIntensity, in: 0...1).tint(.white)
                        }
                        HStack {
                            Spacer()
                            ActionChip(title: "Áp dụng", icon: "camera.aperture", tint: .green) {
                                Task { await model.applyBokeh(intensity: bokehIntensity) }
                            }
                        }
                    }
                }

                section("Xoá vật thể") {
                    VStack(alignment: .leading, spacing: 6) {
                        ActionChip(title: "Quẹt vùng cần xoá", icon: "paintbrush.pointed") {
                            onStartInpaint()
                        }
                        if model.hasNeuralInpaint {
                            Label("Đang dùng model LaMa (AI) — xoá sạch", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Text("Chưa có model LaMa — đang dùng chế độ xấp xỉ. Xem docs/LAMA_MODEL.md để thêm model AI xoá sạch hơn.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
