//
//  SelectiveMaskOverlay.swift
//  editimage
//
//  Handle kéo vùng chọn trên canvas: tâm + đường tròn (radial) hoặc 2 điểm mút (linear).
//

import SwiftUI

struct SelectiveMaskOverlay: View {
    @Bindable var model: EditorViewModel
    let maskID: UUID
    let rect: CGRect

    private var index: Int? { model.graph.masks.firstIndex { $0.id == maskID } }

    var body: some View {
        if let i = index {
            switch model.graph.masks[i].shape {
            case .radial(let center, let radius, _):
                radialHandles(index: i, center: center, radius: radius)
            case .linear(let start, let end):
                linearHandles(index: i, start: start, end: end)
            case .brush:
                EmptyView()
            }
        }
    }

    // MARK: - Radial

    private func radialHandles(index: Int, center: CGPoint, radius: Double) -> some View {
        let c = pt(center)
        let r = radius * min(rect.width, rect.height)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .frame(width: r * 2, height: r * 2)
                .position(c)
            handle.position(c)
                .gesture(DragGesture()
                    .onChanged { v in setRadialCenter(index, location: v.location) }
                    .onEnded { _ in model.commitHistory() })
        }
    }

    private func setRadialCenter(_ index: Int, location: CGPoint) {
        guard case .radial(_, let r, let f) = model.graph.masks[index].shape else { return }
        model.graph.masks[index].shape = .radial(center: norm(location), radius: r, feather: f)
    }

    // MARK: - Linear

    private func linearHandles(index: Int, start: CGPoint, end: CGPoint) -> some View {
        let s = pt(start), e = pt(end)
        return ZStack {
            Path { p in p.move(to: s); p.addLine(to: e) }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            handle.position(s)
                .gesture(DragGesture()
                    .onChanged { v in setLinear(index, start: norm(v.location), end: nil) }
                    .onEnded { _ in model.commitHistory() })
            handle.position(e)
                .gesture(DragGesture()
                    .onChanged { v in setLinear(index, start: nil, end: norm(v.location)) }
                    .onEnded { _ in model.commitHistory() })
        }
    }

    private func setLinear(_ index: Int, start: CGPoint?, end: CGPoint?) {
        guard case .linear(let s, let e) = model.graph.masks[index].shape else { return }
        model.graph.masks[index].shape = .linear(start: start ?? s, end: end ?? e)
    }

    // MARK: - Helpers

    private var handle: some View {
        Circle().fill(.white).frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
            .shadow(radius: 2)
    }

    private func pt(_ p: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    private func norm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - rect.minX) / rect.width, 0), 1),
                y: min(max((p.y - rect.minY) / rect.height, 0), 1))
    }
}
