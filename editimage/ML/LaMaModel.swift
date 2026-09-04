//
//  LaMaModel.swift
//  editimage
//
//  Inference LaMa (Core ML) thật cho xoá vật thể (inpainting) offline.
//
//  Cách thêm model (xem docs/LAMA_MODEL.md):
//   - Kéo `LaMa.mlpackage` vào Xcode target (Xcode tự biên dịch), HOẶC
//   - Đặt `LaMa.mlpackage` / `LaMa.mlmodelc` vào thư mục Application Support của app.
//
//  Code tự dò tên & kiểu I/O của model (image hoặc multiArray) nên khớp với hầu hết
//  bản convert (vd CoreMLaMa). Chỉ chạy inpaint trên vùng cắt quanh mask để tiết kiệm RAM.
//

import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class LaMaModel {
    static let shared = LaMaModel()
    private init() {}

    private var cachedModel: MLModel?
    private let context = RenderEngine.shared.ciContext

    // MARK: - Phát hiện & nạp model

    var isAvailable: Bool { resolveURL() != nil }

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private func resolveURL() -> URL? {
        // 1) Đã biên dịch sẵn trong bundle (Xcode compile .mlpackage -> .mlmodelc).
        if let u = Bundle.main.url(forResource: "LaMa", withExtension: "mlmodelc") { return u }
        // 2) Đã biên dịch trong Application Support.
        let compiled = appSupportDir.appendingPathComponent("LaMa.mlmodelc")
        if FileManager.default.fileExists(atPath: compiled.path) { return compiled }
        // 3) Gói .mlpackage trong Application Support -> biên dịch rồi cache.
        let pkg = appSupportDir.appendingPathComponent("LaMa.mlpackage")
        if FileManager.default.fileExists(atPath: pkg.path),
           let c = try? MLModel.compileModel(at: pkg) {
            try? FileManager.default.removeItem(at: compiled)
            try? FileManager.default.copyItem(at: c, to: compiled)
            return compiled
        }
        return nil
    }

    private func model() -> MLModel? {
        if let cachedModel { return cachedModel }
        guard let url = resolveURL() else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all   // Neural Engine + GPU
        cachedModel = try? MLModel(contentsOf: url, configuration: config)
        return cachedModel
    }

    /// Giải phóng model khỏi RAM (gọi khi máy yếu / rời tính năng).
    func unload() { cachedModel = nil }

    // MARK: - Inpaint

    /// Xoá vùng mask (trắng = xoá) khỏi ảnh bằng LaMa. Trả ảnh đã lấp.
    func inpaint(image: CIImage, mask: CIImage) throws -> CIImage {
        guard let model = model() else { throw AIError.modelUnavailable }

        let extent = image.extent
        // Cắt vùng quanh mask (đệm 30%) để tiết kiệm RAM & tăng tốc.
        let box = maskBoundingBox(mask, in: extent) ?? extent
        let crop = box.insetBy(dx: -box.width * 0.3, dy: -box.height * 0.3).intersection(extent)
        guard !crop.isNull, crop.width > 4, crop.height > 4 else { throw AIError.maskFailed }

        let cropImage = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))
        let cropMask = mask.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.origin.x, y: -crop.origin.y))

        // Kích thước đầu vào model.
        let desc = model.modelDescription
        let (imageKey, maskKey) = inputKeys(desc)
        let (mw, mh) = inputSize(desc, key: imageKey, fallback: 512)

        // Dựng feature đầu vào theo kiểu model yêu cầu (image hoặc multiArray).
        var features: [String: MLFeatureValue] = [:]
        features[imageKey] = try featureValue(for: cropImage, key: imageKey, desc: desc, width: mw, height: mh, isMask: false)
        if let maskKey {
            features[maskKey] = try featureValue(for: cropMask, key: maskKey, desc: desc, width: mw, height: mh, isMask: true)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        let result = try model.prediction(from: provider)

        // Đọc đầu ra (image hoặc multiArray) -> CIImage ở kích thước model.
        guard let outName = desc.outputDescriptionsByName.keys.first,
              let outValue = result.featureValue(for: outName),
              let outImage = ciImage(from: outValue) else {
            throw AIError.maskFailed
        }

        // Scale kết quả về đúng vùng crop, đặt lại toạ độ.
        let sx = crop.width / outImage.extent.width
        let sy = crop.height / outImage.extent.height
        let restored = outImage
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: crop.origin.x - outImage.extent.origin.x * sx,
                                               y: crop.origin.y - outImage.extent.origin.y * sy))
            .cropped(to: crop)
            .clampedToExtent()

        // Chỉ thay phần trong mask (feather mềm), giữ nguyên phần ngoài.
        let softMask = mask.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2]).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = restored
        blend.backgroundImage = image
        blend.maskImage = softMask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - I/O helpers

    private func inputKeys(_ desc: MLModelDescription) -> (image: String, mask: String?) {
        let names = Array(desc.inputDescriptionsByName.keys)
        let imageKey = names.first { $0.lowercased().contains("image") || $0.lowercased().contains("img") } ?? names.first ?? "image"
        let maskKey = names.first { $0.lowercased().contains("mask") }
        return (imageKey, maskKey)
    }

    private func inputSize(_ desc: MLModelDescription, key: String, fallback: Int) -> (Int, Int) {
        guard let input = desc.inputDescriptionsByName[key] else { return (fallback, fallback) }
        if let c = input.imageConstraint, c.pixelsWide > 0, c.pixelsHigh > 0 {
            return (c.pixelsWide, c.pixelsHigh)
        }
        if let m = input.multiArrayConstraint {
            let shape = m.shape.map { $0.intValue }
            // Giả định NCHW: [..., H, W].
            if shape.count >= 2 { return (max(shape[shape.count - 1], 1), max(shape[shape.count - 2], 1)) }
        }
        return (fallback, fallback)
    }

    private func featureValue(for image: CIImage, key: String, desc: MLModelDescription,
                              width: Int, height: Int, isMask: Bool) throws -> MLFeatureValue {
        let input = desc.inputDescriptionsByName[key]
        if input?.type == .image, let constraint = input?.imageConstraint {
            guard let pb = pixelBuffer(from: image, width: width, height: height,
                                       format: constraint.pixelFormatType) else { throw AIError.maskFailed }
            return MLFeatureValue(pixelBuffer: pb)
        }
        // multiArray (NCHW float32, 0...1). Mask 1 kênh, ảnh 3 kênh.
        let channels = isMask ? 1 : 3
        guard let array = multiArray(from: image, width: width, height: height, channels: channels) else {
            throw AIError.maskFailed
        }
        return MLFeatureValue(multiArray: array)
    }

    private func ciImage(from value: MLFeatureValue) -> CIImage? {
        if value.type == .image, let pb = value.imageBufferValue {
            return CIImage(cvPixelBuffer: pb)
        }
        if value.type == .multiArray, let array = value.multiArrayValue {
            return ciImage(fromMultiArray: array)
        }
        return nil
    }

    // MARK: - Pixel buffer / MultiArray

    private func pixelBuffer(from image: CIImage, width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(nil, width, height, format, attrs, &pb)
        guard let buffer = pb else { return nil }
        let scaled = scale(image, toWidth: width, height: height)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        context.render(scaled, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: space)
        return buffer
    }

    private func multiArray(from image: CIImage, width: Int, height: Int, channels: Int) -> MLMultiArray? {
        guard let buffer = pixelBuffer(from: image, width: width, height: height,
                                       format: kCVPixelFormatType_32BGRA) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let array = try? MLMultiArray(shape: [1, NSNumber(value: channels), NSNumber(value: height), NSNumber(value: width)], dataType: .float32)
        guard let array else { return nil }
        let out = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let planeHW = height * width

        for y in 0..<height {
            let row = ptr + y * bytesPerRow
            for x in 0..<width {
                let px = row + x * 4          // BGRA
                let b = Float32(px[0]) / 255
                let g = Float32(px[1]) / 255
                let r = Float32(px[2]) / 255
                let idx = y * width + x
                if channels == 1 {
                    out[idx] = (r + g + b) / 3   // luminance cho mask
                } else {
                    out[idx] = r                 // R plane
                    out[planeHW + idx] = g       // G plane
                    out[2 * planeHW + idx] = b   // B plane
                }
            }
        }
        return array
    }

    private func ciImage(fromMultiArray array: MLMultiArray) -> CIImage? {
        let shape = array.shape.map { $0.intValue }
        guard shape.count >= 2 else { return nil }
        let width = shape[shape.count - 1]
        let height = shape[shape.count - 2]
        let channels = shape.count >= 3 ? shape[shape.count - 3] : 1
        let planeHW = height * width
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)

        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        // Nhiều model xuất giá trị 0...1; một số 0...255. Tự dò để chuẩn hoá.
        var maxVal: Float32 = 0
        for i in 0..<min(planeHW * min(channels, 3), array.count) { maxVal = max(maxVal, ptr[i]) }
        let scaleFactor: Float32 = maxVal > 2 ? 1 : 255

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let o = idx * 4
                func norm(_ v: Float32) -> UInt8 { UInt8(min(max(v * scaleFactor, 0), 255)) }
                if channels >= 3 {
                    bytes[o] = norm(ptr[2 * planeHW + idx])   // B
                    bytes[o + 1] = norm(ptr[planeHW + idx])   // G
                    bytes[o + 2] = norm(ptr[idx])             // R
                } else {
                    let v = norm(ptr[idx]); bytes[o] = v; bytes[o + 1] = v; bytes[o + 2] = v
                }
                bytes[o + 3] = 255
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return bytes.withUnsafeMutableBytes { raw -> CIImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return nil }
            return CIImage(cgImage: cg)
        }
    }

    // MARK: - Utils

    private func scale(_ image: CIImage, toWidth width: Int, height: Int) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return image }
        let sx = CGFloat(width) / e.width
        let sy = CGFloat(height) / e.height
        return image
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: -e.origin.x * sx, y: -e.origin.y * sy))
    }

    /// Bounding box của vùng trắng trong mask (quét bản thu nhỏ).
    private func maskBoundingBox(_ mask: CIImage, in extent: CGRect) -> CGRect? {
        let sample = 96
        guard let pb = pixelBuffer(from: mask, width: sample, height: sample, format: kCVPixelFormatType_32BGRA) else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var minX = sample, minY = sample, maxX = -1, maxY = -1
        for y in 0..<sample {
            let row = ptr + y * bpr
            for x in 0..<sample where row[x * 4 + 2] > 40 {   // R > ngưỡng
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // Lưu ý: pixel buffer gốc trên-trái; extent Core Image gốc dưới-trái -> lật Y.
        let fx = extent.width / CGFloat(sample)
        let fy = extent.height / CGFloat(sample)
        let x0 = extent.origin.x + CGFloat(minX) * fx
        let x1 = extent.origin.x + CGFloat(maxX + 1) * fx
        let y0 = extent.origin.y + CGFloat(sample - 1 - maxY) * fy
        let y1 = extent.origin.y + CGFloat(sample - minY) * fy
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
