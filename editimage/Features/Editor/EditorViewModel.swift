//
//  EditorViewModel.swift
//  editimage
//
//  Bộ não của editor. Giữ ảnh gốc (lazy), bản preview, danh sách AIOp (đã bake +
//  cache), edit graph "rẻ", lịch sử undo/redo, và điều phối export.
//

import SwiftUI
import PhotosUI
import CoreImage

@Observable
@MainActor
final class EditorViewModel {
    // MARK: - Nguồn ảnh
    private(set) var originalFull: CIImage?      // full-res, để export
    private(set) var originalPreview: CIImage?   // downscale để chỉnh real-time
    private var aiBasePreview: CIImage?          // preview sau khi bake AIOp (cache)
    private(set) var originalData: Data?         // dữ liệu ảnh gốc (để lưu dự án)

    // MARK: - Trạng thái chỉnh sửa
    var graph = EditGraph() {
        didSet { recompileCheap() }
    }
    private(set) var aiOps: [AIOp] = []

    // MARK: - Đầu ra hiển thị
    private(set) var displayImage: CIImage?
    var showOriginal = false { didSet { recompileCheap() } }

    // MARK: - Cờ trạng thái
    private(set) var hasImage = false
    private(set) var isLoading = false
    private(set) var isProcessingAI = false
    var aiProgressText = ""
    var errorMessage: String?

    // MARK: - Hạ tầng
    private let engine = RenderEngine.shared
    private let tier = DeviceTier.current
    private let history = HistoryManager()

    /// Kích thước bản preview gốc (px) — dùng để render mask inpaint đúng tỉ lệ.
    var basePreviewSize: CGSize { originalPreview?.extent.size ?? .zero }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var hasNeuralInpaint: Bool { Inpainter.shared.hasNeuralModel }

    // MARK: - Import

    func load(item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoading = true
        defer { isLoading = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Không đọc được ảnh."
            return
        }
        load(data: data)
    }

    func load(data: Data) {
        loadInternal(data: data, graph: EditGraph(), aiOps: [])
    }

    /// Mở lại một dự án đã lưu (ảnh gốc + graph + AIOp).
    func loadProject(data: Data, graph: EditGraph, aiOps: [AIOp]) {
        loadInternal(data: data, graph: graph, aiOps: aiOps)
    }

    private func loadInternal(data: Data, graph newGraph: EditGraph, aiOps newOps: [AIOp]) {
        guard let full = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            errorMessage = "Không mở được ảnh."
            return
        }
        originalData = data
        originalFull = full
        originalPreview = engine.downscaled(full, maxDimension: tier.maxPreviewDimension)
        aiBasePreview = originalPreview
        aiOps = newOps
        graph = newGraph
        hasImage = true
        history.seed(EditSnapshot(graph: graph, aiOps: aiOps))
        if newOps.isEmpty {
            recompileCheap()
        } else {
            Task { await rebuildAIBase(commit: false) }
        }
    }

    // MARK: - Serialize để lưu dự án

    var graphJSON: Data { (try? JSONEncoder().encode(graph)) ?? Data() }
    var aiOpsJSON: Data { (try? JSONEncoder().encode(aiOps)) ?? Data() }

    /// Ảnh thumbnail nhỏ (JPEG) cho gallery — có bake cả chữ.
    func makeThumbnail(maxDimension: CGFloat = 400) -> Data? {
        let baked = GraphCompiler.apply(graph, to: currentBase, includeOverlays: true)
        guard let img = baked ?? originalPreview else { return nil }
        guard let ui = engine.uiImage(from: img, maxDimension: maxDimension) else { return nil }
        return ui.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Render (rẻ)

    private var currentBase: CIImage? { aiBasePreview ?? originalPreview }

    private func recompileCheap() {
        if showOriginal {
            displayImage = originalPreview
        } else {
            // Không bake ảnh chồng/chữ vào preview — vẽ bằng overlay SwiftUI (WYSIWYG).
            displayImage = GraphCompiler.apply(graph, to: currentBase, includeOverlays: false)
        }
    }

    // MARK: - History

    /// Gọi khi 1 thao tác kết thúc (nhả slider, chọn filter, xong AI...).
    func commitHistory() {
        history.commit(EditSnapshot(graph: graph, aiOps: aiOps))
    }

    func undo() {
        guard let snap = history.undo() else { return }
        restore(snap)
    }

    func redo() {
        guard let snap = history.redo() else { return }
        restore(snap)
    }

    private func restore(_ snap: EditSnapshot) {
        let aiChanged = snap.aiOps != aiOps
        aiOps = snap.aiOps
        graph = snap.graph   // didSet -> recompileCheap()
        if aiChanged {
            Task { await rebuildAIBase(commit: false) }
        }
    }

    func resetAll() {
        graph.reset()
        aiOps.removeAll()
        aiBasePreview = originalPreview
        recompileCheap()
        commitHistory()
    }

    // MARK: - Geometry actions

    func rotate90() { graph.geometry.quarterTurns = (graph.geometry.quarterTurns + 1) % 4; commitHistory() }
    func flipHorizontal() { graph.geometry.flipH.toggle(); commitHistory() }
    func flipVertical() { graph.geometry.flipV.toggle(); commitHistory() }
    func setCrop(_ rect: CGRect) { graph.geometry.cropRect = rect; commitHistory() }
    func resetCrop() { graph.geometry = .identity; commitHistory() }

    // MARK: - Filter

    func selectFilter(id: String?) { graph.lutID = id; commitHistory() }

    // MARK: - Selective mask

    // MARK: - Retouch

    func addHealSpot(center: CGPoint, radius: Double) {
        graph.retouch.spots.append(HealSpot(center: center, radius: radius))
        commitHistory()
    }

    func addBrushMask(maskPNG: Data) {
        var mask = SelectiveMask(shape: .brush(maskPNG: maskPNG))
        mask.adjust.exposure = 0.3
        graph.masks.append(mask)
        commitHistory()
    }

    // MARK: - AI actions

    /// Bake lại toàn bộ AIOp lên bản preview (chạy nền).
    private func rebuildAIBase(commit: Bool) async {
        guard let source = originalPreview else { return }
        if aiOps.isEmpty {
            aiBasePreview = source
            recompileCheap()
            if commit { commitHistory() }
            return
        }
        isProcessingAI = true
        defer { isProcessingAI = false }
        let ops = aiOps
        do {
            let baked = try await Task.detached(priority: .userInitiated) {
                try AIProcessor.bake(ops, onto: source)
            }.value
            aiBasePreview = baked
            recompileCheap()
            if commit { commitHistory() }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // rollback op vừa thêm
            if !aiOps.isEmpty { aiOps.removeLast() }
        }
    }

    func removeBackground(fill: BackgroundFill) async {
        aiProgressText = "Đang tách nền…"
        aiOps.append(.removeBackground(fill: fill))
        await rebuildAIBase(commit: true)
    }

    func applyBokeh(intensity: Double) async {
        aiProgressText = "Đang xoá phông…"
        // Bokeh thay thế bokeh cũ (nếu có) thay vì chồng.
        aiOps.removeAll { if case .bokeh = $0 { return true }; return false }
        aiOps.append(.bokeh(intensity: intensity))
        await rebuildAIBase(commit: true)
    }

    func applyInpaint(maskPNG: Data) async {
        aiProgressText = "Đang xoá vật thể…"
        aiOps.append(.inpaint(maskPNG: maskPNG))
        await rebuildAIBase(commit: true)
    }

    // MARK: - Export

    func export(format: ExportFormat = .heif) async -> Bool {
        guard let full = originalFull else { return false }
        isProcessingAI = true
        aiProgressText = "Đang xuất ảnh…"
        defer { isProcessingAI = false }
        do {
            let ops = aiOps
            let g = graph
            try await Task.detached(priority: .userInitiated) {
                try await ExportService.saveToPhotos(original: full, aiOps: ops, graph: g, format: format)
            }.value
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Bindings cho slider adjustments

    private func binding(_ keyPath: WritableKeyPath<Adjustments, Double>) -> Binding<Double> {
        Binding(
            get: { self.graph.adjustments[keyPath: keyPath] },
            set: { self.graph.adjustments[keyPath: keyPath] = $0 }
        )
    }

    var exposure: Binding<Double>    { binding(\.exposure) }
    var brightness: Binding<Double>  { binding(\.brightness) }
    var contrast: Binding<Double>    { binding(\.contrast) }
    var highlights: Binding<Double>  { binding(\.highlights) }
    var shadows: Binding<Double>     { binding(\.shadows) }
    var temperature: Binding<Double> { binding(\.temperature) }
    var tint: Binding<Double>        { binding(\.tint) }
    var saturation: Binding<Double>  { binding(\.saturation) }
    var vibrance: Binding<Double>    { binding(\.vibrance) }
    var sharpness: Binding<Double>   { binding(\.sharpness) }
    var clarity: Binding<Double>     { binding(\.clarity) }
    var vignette: Binding<Double>    { binding(\.vignette) }
    var grain: Binding<Double>       { binding(\.grain) }

    var lutIntensity: Binding<Double> {
        Binding(get: { self.graph.lutIntensity }, set: { self.graph.lutIntensity = $0 })
    }
}
