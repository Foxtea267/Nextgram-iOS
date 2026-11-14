import Foundation

/// In-memory, chat-scoped and capped at five minutes. Never disables filtering in notifications or search.
public final class NextgramTemporaryFilterReveal {
    public static let shared = NextgramTemporaryFilterReveal()
    private let lock = NSLock()
    private var deadlines: [String: TimeInterval] = [:]
    private var timers: [String: DispatchWorkItem] = [:]
    private init() {}

    public func isActive(accountId: Int64, chatId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (self.deadlines["\(accountId).\(chatId)"] ?? 0) > ProcessInfo.processInfo.systemUptime
    }

    public func setActive(_ active: Bool, accountId: Int64, chatId: Int64) {
        let key = "\(accountId).\(chatId)"
        self.lock.lock()
        self.timers.removeValue(forKey: key)?.cancel()
        if active {
            let deadline = ProcessInfo.processInfo.systemUptime + 300
            self.deadlines[key] = deadline
            let timer = DispatchWorkItem { [weak self] in self?.expire(key: key, deadline: deadline) }
            self.timers[key] = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timer)
        } else { self.deadlines.removeValue(forKey: key) }
        self.lock.unlock()
        NotificationCenter.default.post(name: .nagramRegexFiltersDidChange, object: nil)
    }

    private func expire(key: String, deadline: TimeInterval) {
        self.lock.lock()
        guard self.deadlines[key] == deadline else { self.lock.unlock(); return }
        self.deadlines.removeValue(forKey: key)
        self.timers.removeValue(forKey: key)
        self.lock.unlock()
        NotificationCenter.default.post(name: .nagramRegexFiltersDidChange, object: nil)
    }
}
