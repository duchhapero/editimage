//
//  CollageRenderer.swift
//  editimage
//
//  Gộp nhiều ảnh theo bố cục lưới thành 1 ảnh (PNG Data). Dùng cùng công thức
//  vẽ với CollageCellView để preview khớp kết quả xuất.
//

import UIKit

enum CollageRenderer {
    /// Vẽ ảnh aspect-fill vào 1 ô, có zoom/offset + bo góc. Dùng chung cho render & preview logic.
    static func drawFrame(for image: UIImage, in cellRect: CGRect, transform: CellTransform) -> CGRect {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return cellRect }
        let fillScale = max(cellRect.width / imgSize.width, cellRect.height / imgSize.height)
        let s = fillScale * transform.scale
        let drawW = imgSize.width * s
        let drawH = imgSize.height * s
        let cx = cellRect.midX + transform.offset.width * cellRect.width
        let cy = cellRect.midY + transform.offset.height * cellRect.height
        return CGRect(x: cx - drawW / 2, y: cy - drawH / 2, width: drawW, height: drawH)
    }

    static func render(images: [UIImage],
                       transforms: [CellTransform],
                       layout: CollageLayout,
                       aspect: CGFloat,
                       gapFraction: CGFloat,
                       cornerFraction: CGFloat,
                       background: UIColor,
                       longSide: CGFloat = 2048) -> Data? {
        guard !images.isEmpty else { return nil }

        let outSize: CGSize = aspect >= 1
            ? CGSize(width: longSide, height: longSide / aspect)
            : CGSize(width: longSide * aspect, height: longSide)

        let gap = gapFraction * outSize.width

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)

        let image = renderer.image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: outSize))

            for (i, frame) in layout.frames.enumerated() where i < images.count {
                let rawRect = CGRect(x: frame.origin.x * outSize.width,
                                     y: frame.origin.y * outSize.height,
                                     width: frame.width * outSize.width,
                                     height: frame.height * outSize.height)
                let cellRect = rawRect.insetBy(dx: gap / 2, dy: gap / 2)
                let corner = cornerFraction * min(cellRect.width, cellRect.height)
                let transform = i < transforms.count ? transforms[i] : CellTransform()

                context.cgContext.saveGState()
                UIBezierPath(roundedRect: cellRect, cornerRadius: corner).addClip()
                let drawRect = drawFrame(for: images[i], in: cellRect, transform: transform)
                images[i].draw(in: drawRect)
                context.cgContext.restoreGState()
            }
        }
        return image.pngData()
    }
}
