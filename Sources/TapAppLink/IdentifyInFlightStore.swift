import Foundation

/// Coalesces concurrent identical `setAppUserId` calls into one in-flight Task.
/// Locking stays in synchronous methods so it is safe to call from async contexts.
final class IdentifyInFlightStore: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [String: Task<[String: Any], Error>] = [:]

  func coalesce(
    _ appUserId: String,
    create: () -> Task<[String: Any], Error>
  ) -> Task<[String: Any], Error> {
    lock.lock()
    if let existing = tasks[appUserId] {
      lock.unlock()
      return existing
    }
    let task = create()
    tasks[appUserId] = task
    lock.unlock()
    return task
  }

  func remove(_ appUserId: String) {
    lock.lock()
    tasks.removeValue(forKey: appUserId)
    lock.unlock()
  }

  func removeAll() {
    lock.lock()
    tasks.removeAll()
    lock.unlock()
  }
}
