//
//  DeviceTier.swift
//  editimage
//
//  Phân tầng năng lực thiết bị để chọn tham số render/ML thích ứng.
//  Máy mạnh (Pro Max) chạy chất lượng cao nhất; iPhone 12 tự giảm để ổn định.
//

import Foundation
import Metal

/// Tầng năng lực thiết bị, quyết định trần chất lượng của engine.
enum DeviceTier {
    /// iPhone 15/16/17 Pro(Max) và các máy ≥ 6GB RAM.
    case high
    /// iPhone 12 và các máy ~4GB RAM — sàn tối thiểu, ưu tiên ổn định.
    case low

    /// Tier hiện tại của thiết bị, tính 1 lần khi khởi động.
    static let current: DeviceTier = {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        // Ngưỡng 5.5GB: iPhone 12/13 (4GB) -> low; 13 Pro/14 Pro+ (6-8GB) -> high.
        return ramGB >= 5.5 ? .high : .low
    }()

    /// Cạnh dài tối đa của ảnh preview khi chỉnh sửa (điểm ảnh).
    var maxPreviewDimension: CGFloat {
        switch self {
        case .high: return 4096
        case .low:  return 2048
        }
    }

    /// Cạnh dài tối đa của vùng đưa vào model inpainting (LaMa) một lần.
    var maxInpaintDimension: CGFloat {
        switch self {
        case .high: return 2048
        case .low:  return 1024
        }
    }

    /// Có nên giữ model ML thường trú trong RAM (warm) hay unload sau mỗi lần dùng.
    var keepModelsWarm: Bool {
        switch self {
        case .high: return true
        case .low:  return false
        }
    }

    var debugDescription: String {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return "DeviceTier.\(self == .high ? "high" : "low") (RAM ~\(String(format: "%.1f", ramGB))GB)"
    }
}
