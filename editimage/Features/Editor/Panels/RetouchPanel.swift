//
//  RetouchPanel.swift
//  editimage
//
//  Retouch chân dung: làm mịn da + xoá mụn (chạm vào nốt trên ảnh).
//

import SwiftUI

struct RetouchPanel: View {
    @Bindable var model: EditorViewModel
    @Binding var spotMode: Bool
    @Binding var spotRadius: Double

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Làm mịn da") {
                    SliderRow(title: "Độ mịn", value: skinBinding, range: 0...1,
                              defaultValue: 0, onCommit: model.commitHistory)
                }

                section("Xoá mụn") {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            spotMode.toggle()
                        } label: {
                            Label(spotMode ? "Đang xoá — chạm vào nốt mụn" : "Bật chế độ xoá mụn",
                                  systemImage: spotMode ? "checkmark.circle.fill" : "bandage")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(spotMode ? Color.green.opacity(0.3) : Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white)
                        }

                        HStack {
                            Text("Cỡ").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $spotRadius, in: 0.01...0.1).tint(.white)
                        }

                        if spotMode {
                            Text("Chạm vào từng nốt — xoá ngay lập tức (không cần nút áp dụng). Xong thì bấm nút Xuất (mũi tên xuống) ở góc trên để lưu ảnh.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        if !model.graph.retouch.spots.isEmpty {
                            ActionChip(title: "Xoá hết nốt (\(model.graph.retouch.spots.count))",
                                       icon: "arrow.uturn.backward", tint: .orange) {
                                model.graph.retouch.spots.removeAll()
                                model.commitHistory()
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var skinBinding: Binding<Double> {
        Binding(get: { model.graph.retouch.skinSmooth },
                set: { model.graph.retouch.skinSmooth = $0 })
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
