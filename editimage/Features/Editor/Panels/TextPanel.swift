//
//  TextPanel.swift
//  editimage
//
//  Panel thêm/sửa chữ. Vị trí chữ kéo trực tiếp trên canvas (xem EditorView).
//

import SwiftUI

struct TextPanel: View {
    @Bindable var model: EditorViewModel
    @Binding var selectedTextID: UUID?

    private let colors = ["#FFFFFF", "#000000", "#FF3B30", "#FFD60A", "#34C759", "#2E7DFF", "#FF5D8F"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ActionChip(title: "Thêm chữ", icon: "plus") { addText() }

                if let index = selectedIndex {
                    editor(for: index)
                } else {
                    Text("Thêm hoặc chạm vào chữ trên ảnh để sửa.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var selectedIndex: Int? {
        guard let id = selectedTextID else { return nil }
        return model.graph.textLayers.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private func editor(for index: Int) -> some View {
        let layer = Binding(
            get: { model.graph.textLayers[index] },
            set: { model.graph.textLayers[index] = $0 }
        )
        VStack(alignment: .leading, spacing: 12) {
            TextField("Nội dung", text: layer.text)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
                .onSubmit(model.commitHistory)

            HStack {
                Text("Cỡ chữ").font(.caption).foregroundStyle(.secondary)
                Slider(value: layer.fontSize, in: 0.03...0.25, onEditingChanged: { if !$0 { model.commitHistory() } })
                    .tint(.white)
            }

            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: layer.wrappedValue.colorHex == hex ? 2 : 0.5))
                        .onTapGesture { layer.wrappedValue.colorHex = hex; model.commitHistory() }
                }
            }

            Toggle("In đậm", isOn: layer.bold)
                .onChange(of: layer.wrappedValue.bold) { model.commitHistory() }

            ActionChip(title: "Xoá chữ", icon: "trash", tint: .red) {
                model.graph.textLayers.remove(at: index)
                selectedTextID = nil
                model.commitHistory()
            }
        }
    }

    private func addText() {
        var layer = TextLayer()
        layer.text = "Chữ mới"
        model.graph.textLayers.append(layer)
        selectedTextID = layer.id
        model.commitHistory()
    }
}
