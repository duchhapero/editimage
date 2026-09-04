//
//  FilterPanel.swift
//  editimage
//
//  Panel chọn filter/preset (LUT) với thumbnail xem trước + slider cường độ.
//

import SwiftUI
import CoreImage

struct FilterPanel: View {
    @Bindable var model: EditorViewModel
    let thumbnailSource: CIImage?

    @State private var thumbnails: [String: UIImage] = [:]

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LUTEngine.presets) { preset in
                        thumb(for: preset)
                    }
                }
                .padding(.horizontal)
            }

            if model.graph.lutID != nil && model.graph.lutID != "original" {
                SliderRow(title: "Cường độ", value: model.lutIntensity, range: 0...1,
                          defaultValue: 1, onCommit: model.commitHistory)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 10)
        .task(id: thumbnailSource != nil) { await buildThumbnails() }
    }

    private func thumb(for preset: FilterPreset) -> some View {
        let isSelected = (model.graph.lutID ?? "original") == preset.id
        return Button {
            model.selectFilter(id: preset.id == "original" ? nil : preset.id)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let img = thumbnails[preset.id] {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                )
                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
    }

    private func buildThumbnails() async {
        guard let source = thumbnailSource, thumbnails.isEmpty else { return }
        let small = RenderEngine.shared.downscaled(source, maxDimension: 160)
        for preset in LUTEngine.presets {
            let filtered = LUTEngine.apply(presetID: preset.id, intensity: 1, to: small)
            if let ui = RenderEngine.shared.uiImage(from: filtered) {
                thumbnails[preset.id] = ui
            }
        }
    }
}
