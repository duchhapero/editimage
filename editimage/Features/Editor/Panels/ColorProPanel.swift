//
//  ColorProPanel.swift
//  editimage
//
//  Panel "Màu Pro": chuyển giữa Curves và HSL (8 dải màu).
//

import SwiftUI

struct ColorProPanel: View {
    @Bindable var model: EditorViewModel

    enum Mode: String, CaseIterable { case curves = "Curves", hsl = "HSL" }
    @State private var mode: Mode = .curves
    @State private var channel: Curves.Channel = .master
    @State private var band = 0

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if mode == .curves { curvesSection } else { hslSection }
        }
        .padding(.top, 8)
    }

    // MARK: - Curves

    private var curvesSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Curves.Channel.allCases) { ch in
                    Button(ch.title) { channel = ch }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(channel == ch ? Color.accentColor : Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Đặt lại") {
                    model.graph.curves[channel] = Curves.diagonal
                    model.commitHistory()
                }
                .font(.caption).tint(.orange)
            }
            .padding(.horizontal)

            CurveEditorView(model: model, channel: channel)
                .padding(.horizontal)
        }
    }

    // MARK: - HSL

    private var hslSection: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<HSL.bandNames.count, id: \.self) { i in
                        Button(HSL.bandNames[i]) { band = i }
                            .font(.caption)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(band == i ? Color.accentColor : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
            }

            SliderRow(title: "Màu (Hue)", value: bandBinding(\.hue), range: -1...1, defaultValue: 0, onCommit: model.commitHistory)
            SliderRow(title: "Bão hoà", value: bandBinding(\.sat), range: -1...1, defaultValue: 0, onCommit: model.commitHistory)
            SliderRow(title: "Sáng", value: bandBinding(\.lum), range: -1...1, defaultValue: 0, onCommit: model.commitHistory)
        }
        .padding(.horizontal)
    }

    private func bandBinding(_ keyPath: WritableKeyPath<HSLBand, Double>) -> Binding<Double> {
        Binding(
            get: { model.graph.hsl.bands[band][keyPath: keyPath] },
            set: { model.graph.hsl.bands[band][keyPath: keyPath] = $0 }
        )
    }
}
