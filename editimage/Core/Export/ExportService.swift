//
//  ExportService.swift
//  editimage
//
//  Render ảnh full-res (color-managed) và lưu vào Photos. Replay AIOp trên ảnh gốc
//  để export đúng chất lượng thay vì phóng to bản preview.
//

import CoreImage
import Photos
import UIKit

enum ExportFormat {
    case heif       // nén tốt, chất lượng cao
    case jpeg
    case png        // giữ trong suốt (khi đã tách nền)
}

enum ExportError: LocalizedError {
    case renderFailed
    case noPermission
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return "Không render được ảnh."
        case .noPermission: return "Chưa được cấp quyền lưu vào Ảnh."
        case .encodeFailed: return "Không mã hoá được ảnh."
        }
    }
}

enum ExportService {
    private static let context = RenderEngine.shared.ciContext

    /// Dựng ảnh kết quả full-res từ ảnh gốc + AIOp + graph.
    static func renderFullResolution(original: CIImage, aiOps: [AIOp], graph: EditGraph) throws -> CIImage {
        var image = original
        if !aiOps.isEmpty {
            image = try AIProcessor.bake(aiOps, onto: image)
        }
        guard let result = GraphCompiler.apply(graph, to: image) else {
            throw ExportError.renderFailed
        }
        return result
    }

    /// Render + lưu vào thư viện Ảnh. Tự chọn PNG nếu ảnh có vùng trong suốt.
    static func saveToPhotos(original: CIImage, aiOps: [AIOp], graph: EditGraph,
                             format: ExportFormat = .heif) async throws {
        let output = try renderFullResolution(original: original, aiOps: aiOps, graph: graph)

        let hasAlpha = aiOps.contains {
            if case .removeBackground(.transparent) = $0 { return true }
            return false
        }
        let chosenFormat: ExportFormat = hasAlpha ? .png : format

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let data: Data
        switch chosenFormat {
        case .heif:
            data = try heifOrThrow(context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace))
        case .jpeg:
            guard let d = context.jpegRepresentation(of: output, colorSpace: colorSpace,
                                                      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]) else {
                throw ExportError.encodeFailed
            }
            data = d
        case .png:
            guard let d = context.pngRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace) else {
                throw ExportError.encodeFailed
            }
            data = d
        }

        try await save(data: data)
    }

    private static func save(data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.noPermission }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}

// Cho phép `throw` trong toán tử ?? khi encode HEIF.
private func heifOrThrow(_ data: Data?) throws -> Data {
    guard let data else { throw ExportError.encodeFailed }
    return data
}
