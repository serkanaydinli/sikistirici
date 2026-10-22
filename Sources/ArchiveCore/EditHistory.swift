import Foundation

public struct EditHistory: Sendable {
    private struct Step: Sendable { let changes: ArchiveChanges; let label: String }
    private var past: [Step] = []
    private var future: [Step] = []
    public private(set) var current = ArchiveChanges()
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoLabel: String? { past.last?.label }
    public var redoLabel: String? { future.last?.label }
    public mutating func record(_ changes: ArchiveChanges, label: String) {
        guard changes != current else { return }
        past.append(Step(changes:current,label:label))
        if past.count > 100 { past.removeFirst() }
        current = changes; future = []
    }
    @discardableResult public mutating func undo() -> ArchiveChanges {
        guard let step = past.popLast() else { return current }
        future.append(Step(changes:current,label:step.label)); current = step.changes; return current
    }
    @discardableResult public mutating func redo() -> ArchiveChanges {
        guard let step = future.popLast() else { return current }
        past.append(Step(changes:current,label:step.label)); current = step.changes; return current
    }
    public mutating func reset() { self = EditHistory() }
}
