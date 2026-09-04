//
//  CollageBuilderView.swift
//  editimage
//
//  Ghép nhiều ảnh vào bố cục lưới -> gộp thành 1 ảnh rồi mở vào editor.
//

import SwiftUI
import PhotosUI

struct CollageBuilderView: View {
    /// Trả về dữ liệu ảnh collage đã gộp.
    let onFinish: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var transforms: [CellTransform] = []

    @State private var layoutIndex = 0
    @State private var aspectIndex = 0
    @State private var gap: CGFloat = 0.012
    @State private var corner: CGFloat = 0.02
    @State private var bgHex = "#FFFFFF"
    @State private var isLoading = false

    private let bgColors = ["#FFFFFF", "#000000", "#8E8E93", "#2E7DFF", "#FF5D8F", "#FFD60A"]

    private var layouts: [CollageLayout] { CollageLayouts.templates(for: photos.count) }
    private var layout: CollageLayout? {
        guard !layouts.isEmpty else { return nil }
        return layouts[min(layoutIndex, layouts.count - 1)]
    }
    private var aspect: CGFloat { CollageLayouts.aspectRatios[aspectIndex].1 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if photos.isEmpty {
                    picker
                } else {
                    VStack(spacing: 0) {
                        canvas
                        controls
                    }
                }
                if isLoading { ProgressView().controlSize(.large).tint(.white) }
            }
            .navigationTitle("Ghép collage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { finish() }.disabled(photos.isEmpty).fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
        .task(id: selection.count) { await loadSelection() }
        .task { debugLoadIfNeeded() }
    }

    private func debugLoadIfNeeded() {
        #if DEBUG
        guard photos.isEmpty,
              ProcessInfo.processInfo.environment["SEED_TOOL"] == "collage" else { return }
        let sizes: [(CGFloat, CGFloat)] = [(600, 800), (800, 600), (700, 700)]
        photos = sizes.map { UIImage(data: DebugSeed.makeTestImageData(size: CGSize(width: $0.0, height: $0.1)))! }
        transforms = Array(repeating: CellTransform(), count: photos.count)
        layoutIndex = 0
        #endif
    }

    // MARK: - Picker (chọn ảnh)

    private var picker: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.grid.2x2").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Chọn 2–4 ảnh để ghép").font(.headline)
            PhotosPicker(selection: $selection, maxSelectionCount: 4, matching: .images) {
                Label("Chọn ảnh", systemImage: "photo.stack")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let rect = fittedRect(in: geo.size, aspect: aspect)
            ZStack {
                Color(hex: bgHex)
                if let layout {
                    ForEach(Array(layout.frames.enumerated()), id: \.offset) { i, frame in
                        if i < photos.count {
                            let cellRect = cellRect(frame, in: rect.size)
                            CollageCellView(
                                image: photos[i],
                                transform: binding(for: i),
                                corner: corner * min(cellRect.width, cellRect.height),
                                onCommit: {}
                            )
                            .frame(width: cellRect.width, height: cellRect.height)
                            .position(x: cellRect.midX, y: cellRect.midY)
                        }
                    }
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private func cellRect(_ frame: CGRect, in size: CGSize) -> CGRect {
        let g = gap * size.width
        return CGRect(x: frame.origin.x * size.width,
                      y: frame.origin.y * size.height,
                      width: frame.width * size.width,
                      height: frame.height * size.height).insetBy(dx: g / 2, dy: g / 2)
    }

    private func binding(for index: Int) -> Binding<CellTransform> {
        Binding(
            get: { index < transforms.count ? transforms[index] : CellTransform() },
            set: { if index < transforms.count { transforms[index] = $0 } }
        )
    }

    // MARK: - Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Bố cục
                labeled("Bố cục") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(layouts.enumerated()), id: \.element.id) { i, l in
                                Button { layoutIndex = i } label: {
                                    LayoutThumb(layout: l)
                                        .frame(width: 46, height: 46)
                                        .overlay(RoundedRectangle(cornerRadius: 6)
                                            .stroke(i == layoutIndex ? Color.accentColor : .clear, lineWidth: 2))
                                }
                            }
                        }
                    }
                }
                // Tỉ lệ
                labeled("Tỉ lệ") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(CollageLayouts.aspectRatios.enumerated()), id: \.offset) { i, item in
                                chip(item.0, active: i == aspectIndex) { aspectIndex = i }
                            }
                        }
                    }
                }
                sliderRow("Khoảng cách", $gap, 0...0.04)
                sliderRow("Bo góc", $corner, 0...0.15)
                // Nền
                labeled("Màu nền") {
                    HStack(spacing: 10) {
                        ForEach(bgColors, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: bgHex == hex ? 2 : 0.5))
                                .onTapGesture { bgHex = hex }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(height: 250)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func sliderRow(_ title: String, _ value: Binding<CGFloat>, _ range: ClosedRange<CGFloat>) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range).tint(.white)
        }
    }

    private func chip(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? Color.accentColor : Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white)
    }

    private func fittedRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        var w = size.width, h = size.width / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    // MARK: - Actions

    private func loadSelection() async {
        guard !selection.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        var loaded: [UIImage] = []
        for item in selection {
            if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                loaded.append(ui)
            }
        }
        photos = loaded
        transforms = Array(repeating: CellTransform(), count: loaded.count)
        layoutIndex = 0
    }

    private func finish() {
        guard let layout else { return }
        if let data = CollageRenderer.render(
            images: photos, transforms: transforms, layout: layout,
            aspect: aspect, gapFraction: gap, cornerFraction: corner,
            background: UIColor(hex: bgHex) ?? .white) {
            onFinish(data)
        }
        dismiss()
    }
}

// MARK: - Cell

struct CollageCellView: View {
    let image: UIImage
    @Binding var transform: CellTransform
    let corner: CGFloat
    let onCommit: () -> Void

    @State private var baseScale: CGFloat?
    @State private var baseOffset: CGSize?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(transform.scale)
                        .offset(x: transform.offset.width * geo.size.width,
                                y: transform.offset.height * geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: corner))
                .contentShape(Rectangle())
                .gesture(gesture(in: geo.size))
        }
    }

    private func gesture(in size: CGSize) -> some Gesture {
        let drag = DragGesture()
            .onChanged { v in
                let base = baseOffset ?? transform.offset
                if baseOffset == nil { baseOffset = transform.offset }
                transform.offset = CGSize(width: base.width + v.translation.width / size.width,
                                          height: base.height + v.translation.height / size.height)
            }
            .onEnded { _ in baseOffset = nil; onCommit() }

        let magnify = MagnifyGesture()
            .onChanged { v in
                let base = baseScale ?? transform.scale
                if baseScale == nil { baseScale = transform.scale }
                transform.scale = min(max(base * v.magnification, 1), 4)
            }
            .onEnded { _ in baseScale = nil; onCommit() }

        return drag.simultaneously(with: magnify)
    }
}

// MARK: - Layout thumbnail

struct LayoutThumb: View {
    let layout: CollageLayout
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                ForEach(Array(layout.frames.enumerated()), id: \.offset) { _, f in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: f.width * geo.size.width - 3, height: f.height * geo.size.height - 3)
                        .position(x: (f.origin.x + f.width / 2) * geo.size.width,
                                  y: (f.origin.y + f.height / 2) * geo.size.height)
                }
            }
        }
    }
}
