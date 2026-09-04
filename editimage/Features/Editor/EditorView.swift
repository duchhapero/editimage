//
//  EditorView.swift
//  editimage
//
//  Màn hình editor chính: canvas Metal + top bar (undo/redo/compare/export) +
//  thanh công cụ (Adjust / Filter / Crop / Effect / AI / Text) + panel tương ứng.
//

import SwiftUI
import PhotosUI
import SwiftData

enum ToolTab: String, CaseIterable, Identifiable {
    case adjust, color, curveSelective, retouch, filter, crop, effect, ai, photo, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .adjust:         return "Chỉnh"
        case .color:          return "Màu Pro"
        case .curveSelective: return "Chọn vùng"
        case .retouch:        return "Chân dung"
        case .filter:         return "Filter"
        case .crop:           return "Cắt"
        case .effect:         return "Hiệu ứng"
        case .ai:             return "AI"
        case .photo:          return "Ghép ảnh"
        case .text:           return "Chữ"
        }
    }
    var icon: String {
        switch self {
        case .adjust:         return "slider.horizontal.3"
        case .color:          return "point.3.connected.trianglepath.dotted"
        case .curveSelective: return "circle.lefthalf.filled"
        case .retouch:        return "face.smiling"
        case .filter:         return "camera.filters"
        case .crop:           return "crop"
        case .effect:         return "sparkles"
        case .ai:             return "wand.and.stars"
        case .photo:          return "photo.on.rectangle.angled"
        case .text:           return "textformat"
        }
    }
}

struct EditorView: View {
    let project: Project

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = EditorViewModel()
    @State private var currentTool: ToolTab = {
        #if DEBUG
        if let t = ProcessInfo.processInfo.environment["SEED_TOOL"], let tab = ToolTab(rawValue: t) {
            return tab
        }
        #endif
        return .adjust
    }()
    @State private var inpaintMode = false
    @State private var selectedTextID: UUID?
    @State private var selectedImageID: UUID?
    @State private var selectedMaskID: UUID?
    @State private var maskBrushMode = false
    @State private var spotMode = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPOT_MODE"] == "1" { return true }
        #endif
        return false
    }()
    @State private var spotRadius: Double = 0.03
    @State private var showExported = false
    @State private var didLoad = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.hasImage {
                VStack(spacing: 0) {
                    topBar
                    canvas
                    if inpaintMode {
                        EmptyView()   // controls nằm trong overlay
                    } else {
                        panelContainer
                        tabBar
                    }
                }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }

            if model.isProcessingAI || model.isLoading {
                processingOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            model.loadProject(data: project.originalData, graph: project.graph, aiOps: project.aiOps)
        }
        .onDisappear { saveProject() }
        .alert("Lỗi", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Đã lưu vào Ảnh", isPresented: $showExported) {
            Button("OK") {}
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { saveProject(); dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
            }
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)

            Spacer()

            // Giữ để so sánh với ảnh gốc.
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(model.showOriginal ? Color.accentColor : .primary)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.showOriginal = true }
                    .onEnded { _ in model.showOriginal = false })

            Button { model.resetAll() } label: { Image(systemName: "arrow.counterclockwise") }

            Menu {
                Button("HEIF (chất lượng cao)") { export(.heif) }
                Button("JPEG") { export(.jpeg) }
                Button("PNG (giữ trong suốt)") { export(.png) }
            } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 18))
            }
        }
        .font(.system(size: 17))
        .foregroundStyle(.white)
        .padding(.horizontal).padding(.vertical, 10)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                MetalImageView(image: model.displayImage)

                // Ảnh chồng + chữ luôn hiển thị WYSIWYG; sửa được ở tab tương ứng.
                if !inpaintMode {
                    let rect = fittedRect(in: geo.size, aspect: imageAspect)
                    ForEach(model.graph.imageLayers) { layer in
                        ImageLayerView(model: model, layer: layer, rect: rect,
                                       editable: currentTool == .photo,
                                       selectedImageID: $selectedImageID)
                    }
                    ForEach(model.graph.textLayers) { layer in
                        TextLayerView(model: model, layer: layer, rect: rect,
                                      editable: currentTool == .text,
                                      selectedTextID: $selectedTextID)
                    }
                    if currentTool == .curveSelective, let id = selectedMaskID, !maskBrushMode {
                        SelectiveMaskOverlay(model: model, maskID: id, rect: rect)
                    }
                    if currentTool == .retouch {
                        spotOverlay(rect: rect)
                    }
                }

                if inpaintMode {
                    MaskBrushOverlay(
                        imageAspect: imageAspect,
                        maskPixelSize: model.basePreviewSize,
                        onApply: { data in
                            inpaintMode = false
                            Task { await model.applyInpaint(maskPNG: data) }
                        },
                        onCancel: { inpaintMode = false }
                    )
                }

                if maskBrushMode {
                    MaskBrushOverlay(
                        imageAspect: imageAspect,
                        maskPixelSize: model.basePreviewSize,
                        onApply: { data in
                            maskBrushMode = false
                            model.addBrushMask(maskPNG: data)
                            selectedMaskID = model.graph.masks.last?.id
                        },
                        onCancel: { maskBrushMode = false }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var imageAspect: CGFloat {
        let size = model.displayImage?.extent.size ?? CGSize(width: 1, height: 1)
        return size.height > 0 ? size.width / size.height : 1
    }

    private func spotOverlay(rect: CGRect) -> some View {
        let minDim = min(rect.width, rect.height)
        return ZStack {
            ForEach(model.graph.retouch.spots) { spot in
                let d = CGFloat(spot.radius) * minDim * 2
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .overlay(Circle().stroke(Color.green, lineWidth: 2))
                    .frame(width: d, height: d)
                    .position(x: rect.minX + spot.center.x * rect.width,
                              y: rect.minY + spot.center.y * rect.height)
                    .allowsHitTesting(false)
            }
            if spotMode {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        addSpot(at: value.location, rect: rect)
                    })
            }
        }
    }

    private func addSpot(at location: CGPoint, rect: CGRect) {
        guard rect.contains(location) else { return }
        let nx = (location.x - rect.minX) / rect.width
        let ny = (location.y - rect.minY) / rect.height
        model.addHealSpot(center: CGPoint(x: nx, y: ny), radius: spotRadius)
    }

    private func fittedRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        let viewAspect = size.width / size.height
        var w = size.width, h = size.height
        if aspect > viewAspect { h = w / aspect } else { w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    // MARK: - Panel container

    @ViewBuilder
    private var panelContainer: some View {
        Group {
            switch currentTool {
            case .adjust: AdjustPanel(model: model)
            case .color:  ColorProPanel(model: model)
            case .curveSelective: SelectivePanel(model: model, selectedMaskID: $selectedMaskID,
                                                 onStartBrush: { maskBrushMode = true })
            case .retouch: RetouchPanel(model: model, spotMode: $spotMode, spotRadius: $spotRadius)
            case .filter: FilterPanel(model: model, thumbnailSource: model.displayImage)
            case .crop:   CropPanel(model: model)
            case .effect: EffectsPanel(model: model)
            case .ai:     AIPanel(model: model, onStartInpaint: { inpaintMode = true })
            case .photo:  PhotoLayerPanel(model: model, selectedImageID: $selectedImageID)
            case .text:   TextPanel(model: model, selectedTextID: $selectedTextID)
            }
        }
        .frame(height: 230)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ToolTab.allCases) { tab in
                    ToolButton(icon: tab.icon, title: tab.title, isActive: currentTool == tab) {
                        currentTool = tab
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
        .background(Color.black)
    }

    // MARK: - Overlays & actions

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                Text(model.isLoading ? "Đang mở ảnh…" : model.aiProgressText)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func export(_ format: ExportFormat) {
        Task {
            if await model.export(format: format) { showExported = true }
        }
    }

    private func saveProject() {
        guard model.hasImage else { return }
        project.update(graphData: model.graphJSON,
                       aiOpsData: model.aiOpsJSON,
                       thumbnailData: model.makeThumbnail())
        try? context.save()
    }
}

