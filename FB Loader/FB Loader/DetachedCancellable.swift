import Foundation

// `Task.detached` не наследует отмену ожидающей задачи: `.task(id:)` или
// повторная загрузка отменяли бы только ожидание, а фоновая работа шла бы до конца.

nonisolated func runDetachedCancellable<T: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable () async -> T
) async -> T {
    let task = Task.detached(priority: priority) { await operation() }
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

nonisolated func runDetachedCancellable<T: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let task = Task.detached(priority: priority) { try await operation() }
    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}
