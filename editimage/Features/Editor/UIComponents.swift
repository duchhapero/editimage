//
//  UIComponents.swift
//  editimage
//
//  Các thành phần UI dùng lại: hàng slider có nhãn + giá trị, nút công cụ.
//

import SwiftUI

/// Hàng slider có nhãn, giá trị số, double-tap để reset về mặc định.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double = 0
    var onCommit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if !editing { onCommit() }
            })
            .tint(.white)
            .onTapGesture(count: 2) {
                value = defaultValue
                onCommit()
            }
        }
        .padding(.vertical, 2)
    }
}

/// Nút công cụ tròn với icon + nhãn.
struct ToolButton: View {
    let icon: String
    let title: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title).font(.caption2)
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 62, height: 52)
        }
    }
}

/// Nút hành động nhỏ (dùng trong panel).
struct ActionChip: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
        }
    }
}
