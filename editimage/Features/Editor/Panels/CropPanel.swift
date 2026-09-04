//
//  CropPanel.swift
//  editimage
//
//  Panel cắt/xoay/lật. Cắt theo tỉ lệ (crop giữa ảnh), xoay 90°, lật, chỉnh nghiêng.
//

import SwiftUI

struct CropPanel: View {
    @Bindable var model: EditorViewModel

    private let ratios: [(String, CGFloat?)] = [
        ("Tự do", nil), ("1:1", 1), ("4:5", 4.0/5), ("3:4", 3.0/4),
        ("16:9", 16.0/9), ("9:16", 9.0/16),
    ]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ratios, id: \.0) { item in
                        Button(item.0) { applyRatio(item.1) }
                            .font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 20) {
                iconButton("rotate.left", "Xoay") { model.rotate90() }
                iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "Lật ngang") { model.flipHorizontal() }
                iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", "Lật dọc") { model.flipVertical() }
                iconButton("arrow.counterclockwise", "Đặt lại") { model.resetCrop() }
            }

            SliderRow(title: "Chỉnh nghiêng", value: straightenBinding, range: -45...45,
                      defaultValue: 0, onCommit: model.commitHistory)
                .padding(.horizontal)
        }
        .padding(.top, 10)
    }

    private var straightenBinding: Binding<Double> {
        Binding(get: { model.graph.geometry.straighten },
                set: { model.graph.geometry.straighten = $0 })
    }

    private func applyRatio(_ ratio: CGFloat?) {
        guard let ratio else { model.setCrop(CGRect(x: 0, y: 0, width: 1, height: 1)); return }
        // Cắt hình chữ nhật lớn nhất theo tỉ lệ, canh giữa (dựa trên ảnh đang hiển thị).
        let imgSize = model.displayImage?.extent.size ?? CGSize(width: 1, height: 1)
        let imgRatio = imgSize.width / imgSize.height
        var w: CGFloat = 1, h: CGFloat = 1
        if ratio > imgRatio {
            h = imgRatio / ratio
        } else {
            w = ratio / imgRatio
        }
        let rect = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
        model.setCrop(rect)
    }

    private func iconButton(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption2)
            }
            .frame(width: 70, height: 48)
            .foregroundStyle(.white)
        }
    }
}
