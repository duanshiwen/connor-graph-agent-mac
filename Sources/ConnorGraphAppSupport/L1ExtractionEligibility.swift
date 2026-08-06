import Foundation

public final class L1ExtractionEligibility: @unchecked Sendable {
    public static let shared = L1ExtractionEligibility()
    private let lock = NSLock()
    private var leaseExpiresAt: Date?
    /// 后端失联或未登录时本机自行提取的回退模式：只要租约流程重新成功
    /// （拿到后端授予的租约）就立即清除；不设过期时间，避免长时间中断。
    private var localFallbackActive = false
    /// 同步关闭时的独立提取模式：本机不参与后端 L1 租约竞争，始终自行提取。
    /// 只在重新开启同步并收到租约结论后由 update(granted:) 清除。
    private var standaloneLocalMode = false

    private init() {}

    public func update(granted: Bool, expiresAt: Date?) {
        lock.lock(); defer { lock.unlock() }
        leaseExpiresAt = granted ? expiresAt : nil
        // 只要后端可达并给出了租约结论（无论授予与否），都不再使用本地回退或独立模式。
        localFallbackActive = false
        standaloneLocalMode = false
    }

    public func canRun(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if standaloneLocalMode || localFallbackActive { return true }
        return leaseExpiresAt.map { $0 > now } ?? false
    }

    /// 后端失联或未登录时启用本机自行提取（Mac/Android 各自本地执行，不再等后端分配）。
    public func enableLocalFallback() {
        lock.lock(); defer { lock.unlock() }
        leaseExpiresAt = nil
        localFallbackActive = true
        standaloneLocalMode = false
    }

    /// 同步关闭时启用独立提取：本机不参与后端租约竞争，始终自行提取，
    /// 直到重新开启同步并收到租约结论。
    public func enableStandalone() {
        lock.lock(); defer { lock.unlock() }
        leaseExpiresAt = nil
        localFallbackActive = false
        standaloneLocalMode = true
    }

    /// 显式关闭提取资格（本地回退、独立模式与租约都失效）；正常流程下由登录/租约/同步状态驱动，
    /// 仅在需要强制停止时使用。
    public func disable() {
        lock.lock(); defer { lock.unlock() }
        leaseExpiresAt = nil
        localFallbackActive = false
        standaloneLocalMode = false
    }
}
