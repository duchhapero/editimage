//
//  HistoryManager.swift
//  editimage
//
//  Undo/Redo trên trạng thái chỉnh sửa. Snapshot chỉ gồm graph + danh sách AIOp
//  (đều nhẹ, không phải bitmap) nên push/undo rất rẻ.
//

import Foundation

/// Một mốc lịch sử chỉnh sửa.
struct EditSnapshot: Equatable {
    var graph: EditGraph
    var aiOps: [AIOp]
}

final class HistoryManager {
    private(set) var undoStack: [EditSnapshot] = []
    private var redoStack: [EditSnapshot] = []
    private let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    var canUndo: Bool { undoStack.count > 1 }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Ghi mốc khởi đầu (trạng thái gốc). Gọi 1 lần khi mở ảnh.
    func seed(_ snapshot: EditSnapshot) {
        undoStack = [snapshot]
        redoStack.removeAll()
    }

    /// Ghi 1 mốc mới sau khi thao tác kết thúc.
    func commit(_ snapshot: EditSnapshot) {
        guard undoStack.last != snapshot else { return }  // bỏ qua nếu không đổi
        undoStack.append(snapshot)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Undo -> trả snapshot cần khôi phục (nil nếu không undo được).
    func undo() -> EditSnapshot? {
        guard canUndo else { return nil }
        let current = undoStack.removeLast()
        redoStack.append(current)
        return undoStack.last
    }

    /// Redo -> trả snapshot cần khôi phục (nil nếu không redo được).
    func redo() -> EditSnapshot? {
        guard let snapshot = redoStack.popLast() else { return nil }
        undoStack.append(snapshot)
        return snapshot
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
