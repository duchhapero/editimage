//
//  HomeView.swift
//  editimage
//
//  Màn hình chủ: lưới dự án đã lưu + tạo dự án mới từ Photos.
//

import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var pickerItem: PhotosPickerItem?
    @State private var newProject: Project?
    @State private var isImporting = false
    @State private var showCollage = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Ảnh của tôi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCollage = true } label: {
                        Image(systemName: "square.grid.2x2").font(.system(size: 18))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20))
                    }
                }
            }
            .navigationDestination(item: $newProject) { project in
                EditorView(project: project)
            }
            .fullScreenCover(isPresented: $showCollage) {
                CollageBuilderView { data in
                    let project = Project(originalData: data)
                    context.insert(project)
                    try? context.save()
                    newProject = project
                }
            }
            .overlay { if isImporting { importOverlay } }
        }
        .preferredColorScheme(.dark)
        .task(id: pickerItem) { await importPicked() }
        .onAppear { seedIfNeeded() }
    }

    private func seedIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SEED_TOOL"] == "collage" {
            showCollage = true
            return
        }
        guard DebugSeed.isEnabled, projects.isEmpty, newProject == nil else { return }
        var graph = EditGraph()
        graph.adjustments.vignette = 0.3
        // Curves: S-curve tăng tương phản trên kênh RGB.
        graph.curves.master = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.14),
                               CurvePoint(x: 0.75, y: 0.86), CurvePoint(x: 1, y: 1)]
        // HSL: đẩy dải Lam sang tím + tăng bão hoà.
        graph.hsl.bands[5].hue = 0.4
        graph.hsl.bands[5].sat = 0.6
        // Selective: vùng tròn giữa ảnh tăng phơi sáng.
        var mask = SelectiveMask(shape: .radial(center: CGPoint(x: 0.5, y: 0.45), radius: 0.3, feather: 0.6))
        mask.adjust.exposure = 0.8
        mask.adjust.saturation = 1.3
        graph.masks = [mask]
        // Retouch: làm mịn + 2 nốt heal.
        graph.retouch.skinSmooth = 0.6
        graph.retouch.spots = [
            HealSpot(center: CGPoint(x: 0.16, y: 0.2), radius: 0.07),
            HealSpot(center: CGPoint(x: 0.72, y: 0.62), radius: 0.06),
        ]
        var t = TextLayer()
        t.text = "XIN CHÀO"
        t.position = CGPoint(x: 0.5, y: 0.85)
        t.fontSize = 0.09
        t.colorHex = "#FFD60A"
        graph.textLayers = [t]
        var layer = ImageLayer(imageData: DebugSeed.makeTestImageData(size: CGSize(width: 400, height: 400)))
        layer.position = CGPoint(x: 0.35, y: 0.35)
        layer.scale = 0.4
        layer.rotation = -12
        graph.imageLayers = [layer]
        let data = DebugSeed.makeTestImageData()
        let project = Project(originalData: data,
                              graphData: (try? JSONEncoder().encode(graph)) ?? Data())
        context.insert(project)
        try? context.save()
        newProject = project
        #endif
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60)).foregroundStyle(.secondary)
            Text("Chưa có dự án nào").font(.title3.bold())
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Tạo ảnh mới", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            Button { showCollage = true } label: {
                Label("Ghép collage", systemImage: "square.grid.2x2")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(projects) { project in
                    NavigationLink { EditorView(project: project) } label: {
                        thumbnail(project)
                    }
                    .contextMenu {
                        Button("Xoá", systemImage: "trash", role: .destructive) {
                            context.delete(project)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func thumbnail(_ project: Project) -> some View {
        ZStack {
            if let data = project.thumbnailData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.08))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            ProgressView("Đang nhập ảnh…").tint(.white).foregroundStyle(.white)
                .padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Import

    private func importPicked() async {
        guard let item = pickerItem else { return }
        isImporting = true
        defer { isImporting = false; pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let project = Project(originalData: data)
        context.insert(project)
        try? context.save()
        newProject = project
    }
}
