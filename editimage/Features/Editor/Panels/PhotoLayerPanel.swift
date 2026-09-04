//
//  PhotoLayerPanel.swift
//  editimage
//
//  Panel ghép nhiều ảnh: thêm ảnh chồng lên ảnh nền, chỉnh độ mờ + blend mode,
//  xoá. Di chuyển/zoom/xoay trực tiếp trên canvas.
//

import SwiftUI
import PhotosUI

struct PhotoLayerPanel: View {
    @Bindable var model: EditorViewModel
    @Binding var selectedImageID: UUID?

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Thêm ảnh", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }

                if let index = selectedIndex {
                    editor(for: index)
                } else {
                    Text("Thêm ảnh rồi kéo/chụm 2 ngón để chỉnh trên ảnh. Chạm ảnh để chọn.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .task(id: pickerItem) { await addPicked() }
    }

    private var selectedIndex: Int? {
        guard let id = selectedImageID else { return nil }
        return model.graph.imageLayers.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private func editor(for index: Int) -> some View {
        let layer = Binding(
            get: { model.graph.imageLayers[index] },
            set: { model.graph.imageLayers[index] = $0 }
        )
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Độ mờ").font(.caption).foregroundStyle(.secondary)
                Slider(value: layer.opacity, in: 0...1,
                       onEditingChanged: { if !$0 { model.commitHistory() } })
                    .tint(.white)
            }

            HStack {
                Text("Hoà trộn").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(BlendKind.allCases) { kind in
                        Button(kind.label) { layer.wrappedValue.blend = kind; model.commitHistory() }
                    }
                } label: {
                    Text(layer.wrappedValue.blend.label)
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            ActionChip(title: "Xoá lớp ảnh", icon: "trash", tint: .red) {
                model.graph.imageLayers.remove(at: index)
                selectedImageID = nil
                model.commitHistory()
            }
        }
    }

    private func addPicked() async {
        guard let item = pickerItem else { return }
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        var layer = ImageLayer(imageData: data)
        layer.scale = 0.5
        model.graph.imageLayers.append(layer)
        selectedImageID = layer.id
        model.commitHistory()
    }
}
