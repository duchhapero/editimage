//
//  SelectivePanel.swift
//  editimage
//
//  Chỉnh sửa cục bộ theo vùng chọn (mask). Thêm mask Tròn/Dải/Cọ, chỉnh bộ thông số
//  áp trong vùng, đảo vùng, xoá. Di chuyển vùng trực tiếp trên canvas.
//

import SwiftUI

struct SelectivePanel: View {
    @Bindable var model: EditorViewModel
    @Binding var selectedMaskID: UUID?
    var onStartBrush: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ActionChip(title: "Tròn", icon: "circle.dashed") { add(.radial(center: CGPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5)) }
                    ActionChip(title: "Dải", icon: "line.diagonal") { add(.linear(start: CGPoint(x: 0.5, y: 0.2), end: CGPoint(x: 0.5, y: 0.8))) }
                    ActionChip(title: "Cọ", icon: "paintbrush.pointed") { onStartBrush() }
                }

                if let index = selectedIndex {
                    editor(for: index)
                } else {
                    Text("Thêm vùng chọn rồi chỉnh. Kéo vùng trên ảnh để di chuyển.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var selectedIndex: Int? {
        guard let id = selectedMaskID else { return nil }
        return model.graph.masks.firstIndex { $0.id == id }
    }

    @ViewBuilder
    private func editor(for index: Int) -> some View {
        let mask = Binding(
            get: { model.graph.masks[index] },
            set: { model.graph.masks[index] = $0 }
        )
        VStack(spacing: 6) {
            if case .radial = mask.wrappedValue.shape {
                SliderRow(title: "Kích thước", value: radialRadius(mask), range: 0.05...0.9, defaultValue: 0.3, onCommit: model.commitHistory)
                SliderRow(title: "Mềm viền", value: radialFeather(mask), range: 0.05...0.95, defaultValue: 0.5, onCommit: model.commitHistory)
            }
            SliderRow(title: "Phơi sáng", value: adj(mask, \.exposure), range: -2...2, defaultValue: 0, onCommit: model.commitHistory)
            SliderRow(title: "Tương phản", value: adj(mask, \.contrast), range: 0.5...1.5, defaultValue: 1, onCommit: model.commitHistory)
            SliderRow(title: "Bão hoà", value: adj(mask, \.saturation), range: 0...2, defaultValue: 1, onCommit: model.commitHistory)
            SliderRow(title: "Nhiệt độ", value: adj(mask, \.temperature), range: -1...1, defaultValue: 0, onCommit: model.commitHistory)
            SliderRow(title: "Nét", value: adj(mask, \.sharpness), range: 0...2, defaultValue: 0, onCommit: model.commitHistory)

            Toggle("Đảo vùng", isOn: mask.inverted)
                .font(.subheadline)
                .onChange(of: mask.wrappedValue.inverted) { model.commitHistory() }

            ActionChip(title: "Xoá vùng", icon: "trash", tint: .red) {
                model.graph.masks.remove(at: index)
                selectedMaskID = nil
                model.commitHistory()
            }
        }
    }

    // MARK: - Bindings

    private func adj(_ mask: Binding<SelectiveMask>, _ keyPath: WritableKeyPath<LocalAdjust, Double>) -> Binding<Double> {
        Binding(get: { mask.wrappedValue.adjust[keyPath: keyPath] },
                set: { mask.wrappedValue.adjust[keyPath: keyPath] = $0 })
    }

    private func radialRadius(_ mask: Binding<SelectiveMask>) -> Binding<Double> {
        Binding(
            get: { if case .radial(_, let r, _) = mask.wrappedValue.shape { return r }; return 0.3 },
            set: {
                if case .radial(let c, _, let f) = mask.wrappedValue.shape {
                    mask.wrappedValue.shape = .radial(center: c, radius: $0, feather: f)
                }
            }
        )
    }

    private func radialFeather(_ mask: Binding<SelectiveMask>) -> Binding<Double> {
        Binding(
            get: { if case .radial(_, _, let f) = mask.wrappedValue.shape { return f }; return 0.5 },
            set: {
                if case .radial(let c, let r, _) = mask.wrappedValue.shape {
                    mask.wrappedValue.shape = .radial(center: c, radius: r, feather: $0)
                }
            }
        )
    }

    private func add(_ shape: MaskShape) {
        var mask = SelectiveMask(shape: shape)
        mask.adjust.exposure = 0.3   // giá trị mồi để thấy hiệu ứng ngay
        model.graph.masks.append(mask)
        selectedMaskID = mask.id
        model.commitHistory()
    }
}
