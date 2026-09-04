//
//  ImageLayerView.swift
//  editimage
//
//  Hiển thị lớp ảnh chồng WYSIWYG trên canvas. Ở tab Ảnh: kéo di chuyển,
//  chụm 2 ngón phóng to/thu nhỏ, xoay 2 ngón.
//

import SwiftUI

extension BlendKind {
    var swiftUIBlend: BlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .screen:     return .screen
        case .overlay:    return .overlay
        case .darken:     return .darken
        case .lighten:    return .lighten
        case .difference: return .difference
        }
    }
}

struct ImageLayerView: View {
    @Bindable var model: EditorViewModel
    let layer: ImageLayer
    let rect: CGRect
    let editable: Bool
    @Binding var selectedImageID: UUID?

    @State private var baseScale: Double?
    @State private var baseRotation: Double?

    var body: some View {
        let displayWidth = max(layer.scale * rect.width, 8)
        let position = CGPoint(x: rect.minX + layer.position.x * rect.width,
                               y: rect.minY + layer.position.y * rect.height)
        let isSelected = editable && selectedImageID == layer.id

        Group {
            if let ui = UIImage(data: layer.imageData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayWidth)
                    .opacity(layer.opacity)
                    .blendMode(layer.blend.swiftUIBlend)
                    .overlay {
                        if isSelected {
                            Rectangle().strokeBorder(Color.accentColor,
                                                     style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        }
                    }
                    .rotationEffect(.degrees(layer.rotation))
            }
        }
        .position(position)
        .allowsHitTesting(editable)
        .gesture(editable ? combinedGesture : nil)
        .onTapGesture { if editable { selectedImageID = layer.id } }
    }

    private var index: Int? {
        model.graph.imageLayers.firstIndex { $0.id == layer.id }
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                selectedImageID = layer.id
                guard let i = index else { return }
                let nx = min(max((value.location.x - rect.minX) / rect.width, 0), 1)
                let ny = min(max((value.location.y - rect.minY) / rect.height, 0), 1)
                model.graph.imageLayers[i].position = CGPoint(x: nx, y: ny)
            }
            .onEnded { _ in model.commitHistory() }

        let magnify = MagnifyGesture()
            .onChanged { value in
                selectedImageID = layer.id
                guard let i = index else { return }
                let base = baseScale ?? layer.scale
                if baseScale == nil { baseScale = layer.scale }
                model.graph.imageLayers[i].scale = min(max(base * value.magnification, 0.05), 3)
            }
            .onEnded { _ in baseScale = nil; model.commitHistory() }

        let rotate = RotateGesture()
            .onChanged { value in
                selectedImageID = layer.id
                guard let i = index else { return }
                let base = baseRotation ?? layer.rotation
                if baseRotation == nil { baseRotation = layer.rotation }
                model.graph.imageLayers[i].rotation = base + value.rotation.degrees
            }
            .onEnded { _ in baseRotation = nil; model.commitHistory() }

        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
    }
}
