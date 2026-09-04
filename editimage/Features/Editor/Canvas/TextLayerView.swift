//
//  TextLayerView.swift
//  editimage
//
//  Hiển thị chữ WYSIWYG trên canvas (đúng bằng chữ sẽ được bake vào ảnh khi export).
//  Khi ở tab Chữ: kéo để di chuyển, chụm 2 ngón để phóng to/thu nhỏ, xoay 2 ngón.
//

import SwiftUI

struct TextLayerView: View {
    @Bindable var model: EditorViewModel
    let layer: TextLayer
    let rect: CGRect          // khung ảnh hiển thị trên canvas
    let editable: Bool
    @Binding var selectedTextID: UUID?

    @State private var baseFontSize: Double?
    @State private var baseRotation: Double?

    var body: some View {
        let pointSize = max(layer.fontSize * rect.height, 6)
        let position = CGPoint(x: rect.minX + layer.position.x * rect.width,
                               y: rect.minY + layer.position.y * rect.height)
        let isSelected = editable && selectedTextID == layer.id

        Text(layer.text.isEmpty ? " " : layer.text)
            .font(.system(size: pointSize, weight: layer.bold ? .bold : .regular))
            .foregroundStyle(Color(hex: layer.colorHex))
            .shadow(color: .black.opacity(0.5), radius: pointSize * 0.05, y: pointSize * 0.03)
            .fixedSize()
            .padding(4)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
            }
            .rotationEffect(.degrees(layer.rotation))
            .position(position)
            .allowsHitTesting(editable)
            .gesture(editable ? combinedGesture : nil)
            .onTapGesture { if editable { selectedTextID = layer.id } }
    }

    private var index: Int? {
        model.graph.textLayers.firstIndex { $0.id == layer.id }
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                selectedTextID = layer.id
                guard let i = index else { return }
                let nx = min(max((value.location.x - rect.minX) / rect.width, 0), 1)
                let ny = min(max((value.location.y - rect.minY) / rect.height, 0), 1)
                model.graph.textLayers[i].position = CGPoint(x: nx, y: ny)
            }
            .onEnded { _ in model.commitHistory() }

        let magnify = MagnifyGesture()
            .onChanged { value in
                selectedTextID = layer.id
                guard let i = index else { return }
                let base = baseFontSize ?? layer.fontSize
                if baseFontSize == nil { baseFontSize = layer.fontSize }
                model.graph.textLayers[i].fontSize = min(max(base * value.magnification, 0.02), 0.6)
            }
            .onEnded { _ in baseFontSize = nil; model.commitHistory() }

        let rotate = RotateGesture()
            .onChanged { value in
                selectedTextID = layer.id
                guard let i = index else { return }
                let base = baseRotation ?? layer.rotation
                if baseRotation == nil { baseRotation = layer.rotation }
                model.graph.textLayers[i].rotation = base + value.rotation.degrees
            }
            .onEnded { _ in baseRotation = nil; model.commitHistory() }

        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
    }
}
