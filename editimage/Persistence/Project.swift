//
//  Project.swift
//  editimage
//
//  Dự án chỉnh sửa (SwiftData). Lưu ảnh gốc + edit graph + AIOp (không phá hủy),
//  cho phép mở lại và chỉnh tiếp bất cứ lúc nào.
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    /// Ảnh gốc (external storage để không phình DB).
    @Attribute(.externalStorage) var originalData: Data
    /// Thumbnail đã render cho gallery.
    @Attribute(.externalStorage) var thumbnailData: Data?

    /// EditGraph mã hoá JSON.
    var graphData: Data
    /// [AIOp] mã hoá JSON.
    var aiOpsData: Data

    init(originalData: Data,
         graphData: Data = Data(),
         aiOpsData: Data = Data(),
         thumbnailData: Data? = nil) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.originalData = originalData
        self.graphData = graphData
        self.aiOpsData = aiOpsData
        self.thumbnailData = thumbnailData
    }

    // MARK: - Giải mã tiện dụng

    var graph: EditGraph {
        (try? JSONDecoder().decode(EditGraph.self, from: graphData)) ?? EditGraph()
    }

    var aiOps: [AIOp] {
        (try? JSONDecoder().decode([AIOp].self, from: aiOpsData)) ?? []
    }

    func update(graphData: Data, aiOpsData: Data, thumbnailData: Data?) {
        self.graphData = graphData
        self.aiOpsData = aiOpsData
        if let thumbnailData { self.thumbnailData = thumbnailData }
        self.updatedAt = Date()
    }
}
