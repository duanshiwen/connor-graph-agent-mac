import AppKit
import Foundation
import os
import SwiftUI
import ConnorGraphAppSupport

enum AppRoutePane: String, Sendable, Equatable {
    case list
    case detail
}

enum AppRouteActivationKind: String, Sendable, Equatable {
    case mount
    case cacheHit
}

struct AppRoutePerformanceEvent: Sendable, Equatable {
    enum Kind: String, Sendable {
        case began
        case paneActivated
        case panePresented
        case completed
        case cancelled
    }

    var kind: Kind
    var transactionID: UInt64
    var route: SidebarItem
    var pane: AppRoutePane?
    var activationKind: AppRouteActivationKind?
}

@MainActor
final class AppRoutePerformanceTracker {
    typealias EventObserver = @MainActor (AppRoutePerformanceEvent) -> Void

    private struct ActiveTransaction {
        var id: UInt64
        var route: SidebarItem
        var startedAt: UInt64
        var signpostID: OSSignpostID
        var interval: OSSignpostIntervalState
        var activatedPanes: Set<AppRoutePane> = []
        var presentedPanes: Set<AppRoutePane> = []
    }

    private static let signposter = OSSignposter(
        subsystem: AppPerformanceLog.subsystem,
        category: AppPerformanceLog.sidebarNavigationCategory
    )

    private var nextTransactionID: UInt64 = 1
    private var activeTransaction: ActiveTransaction?
    private var completionGeneration: UInt64 = 0
    private let now: () -> UInt64
    private let eventObserver: EventObserver?

    init(
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        eventObserver: EventObserver? = nil
    ) {
        self.now = now
        self.eventObserver = eventObserver
    }

    var activeTransactionID: UInt64? { activeTransaction?.id }
    var activeRoute: SidebarItem? { activeTransaction?.route }

    @discardableResult
    func begin(route: SidebarItem, from previousRoute: SidebarItem?) -> UInt64 {
        cancelActiveTransaction(reason: "superseded")

        let transactionID = nextTransactionID
        nextTransactionID &+= 1
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval(
            "SidebarRoute",
            id: signpostID,
            "transaction=\(transactionID) from=\(previousRoute?.rawValue ?? "none", privacy: .public) to=\(route.rawValue, privacy: .public)"
        )
        activeTransaction = ActiveTransaction(
            id: transactionID,
            route: route,
            startedAt: now(),
            signpostID: signpostID,
            interval: interval
        )
        emit(.init(kind: .began, transactionID: transactionID, route: route))
        return transactionID
    }

    func markActivated(
        route: SidebarItem,
        pane: AppRoutePane,
        activationKind: AppRouteActivationKind = .mount
    ) {
        guard var transaction = activeTransaction,
              transaction.route == route,
              !transaction.activatedPanes.contains(pane)
        else { return }

        transaction.activatedPanes.insert(pane)
        activeTransaction = transaction
        let elapsed = milliseconds(since: transaction.startedAt)
        AppPerformanceLog.sidebarNavigationLogger.info(
            "sidebar.route.hostActivated transaction=\(transaction.id) route=\(route.rawValue, privacy: .public) pane=\(pane.rawValue, privacy: .public) activation=\(activationKind.rawValue, privacy: .public) duration=\(elapsed, privacy: .public)ms"
        )
        Self.signposter.emitEvent(
            "SidebarRoutePaneActivated",
            id: transaction.signpostID,
            "transaction=\(transaction.id) route=\(route.rawValue, privacy: .public) pane=\(pane.rawValue, privacy: .public) activation=\(activationKind.rawValue, privacy: .public)"
        )
        emit(.init(
            kind: .paneActivated,
            transactionID: transaction.id,
            route: route,
            pane: pane,
            activationKind: activationKind
        ))

    }

    func markPresented(route: SidebarItem, pane: AppRoutePane) {
        guard var transaction = activeTransaction,
              transaction.route == route,
              !transaction.presentedPanes.contains(pane)
        else { return }

        transaction.presentedPanes.insert(pane)
        activeTransaction = transaction
        let elapsed = milliseconds(since: transaction.startedAt)
        AppPerformanceLog.sidebarNavigationLogger.info(
            "sidebar.route.contentPresented transaction=\(transaction.id) route=\(route.rawValue, privacy: .public) pane=\(pane.rawValue, privacy: .public) duration=\(elapsed, privacy: .public)ms"
        )
        Self.signposter.emitEvent(
            "SidebarRoutePanePresented",
            id: transaction.signpostID,
            "transaction=\(transaction.id) route=\(route.rawValue, privacy: .public) pane=\(pane.rawValue, privacy: .public)"
        )
        emit(.init(
            kind: .panePresented,
            transactionID: transaction.id,
            route: route,
            pane: pane
        ))

        guard transaction.presentedPanes == Set(AppRoutePane.allCases) else { return }
        scheduleCompletion(for: transaction.id)
    }

    func cancelActiveTransaction(reason: StaticString = "cancelled") {
        completionGeneration &+= 1
        guard let transaction = activeTransaction else { return }
        activeTransaction = nil
        Self.signposter.endInterval(
            "SidebarRoute",
            transaction.interval,
            "transaction=\(transaction.id) route=\(transaction.route.rawValue, privacy: .public) outcome=\(reason, privacy: .public)"
        )
        AppPerformanceLog.sidebarNavigationLogger.debug(
            "sidebar.route.cancelled transaction=\(transaction.id) route=\(transaction.route.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
        emit(.init(kind: .cancelled, transactionID: transaction.id, route: transaction.route))
    }

    private func scheduleCompletion(for transactionID: UInt64) {
        completionGeneration &+= 1
        let generation = completionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  generation == self.completionGeneration,
                  let transaction = self.activeTransaction,
                  transaction.id == transactionID
            else { return }
            self.activeTransaction = nil
            let elapsed = self.milliseconds(since: transaction.startedAt)
            Self.signposter.endInterval(
                "SidebarRoute",
                transaction.interval,
                "transaction=\(transaction.id) route=\(transaction.route.rawValue, privacy: .public) outcome=displayed duration=\(elapsed)ms"
            )
            AppPerformanceLog.sidebarNavigationLogger.info(
                "sidebar.route.displayed transaction=\(transaction.id) route=\(transaction.route.rawValue, privacy: .public) duration=\(elapsed, privacy: .public)ms"
            )
            self.emit(.init(kind: .completed, transactionID: transaction.id, route: transaction.route))
        }
    }

    private func milliseconds(since startedAt: UInt64) -> Double {
        Double(now() &- startedAt) / 1_000_000
    }

    private func emit(_ event: AppRoutePerformanceEvent) {
        eventObserver?(event)
    }
}

extension AppRoutePane: CaseIterable {}

final class AppRouteActivationNSView: NSView {
    var route: SidebarItem = .agentChat
    var pane: AppRoutePane = .list
    var onActivated: ((SidebarItem, AppRoutePane) -> Void)?
    private var lastReportedRoute: SidebarItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportIfNeeded()
    }

    func update(route: SidebarItem, pane: AppRoutePane) {
        self.route = route
        self.pane = pane
        reportIfNeeded()
    }

    private func reportIfNeeded() {
        guard window != nil, lastReportedRoute != route else { return }
        lastReportedRoute = route
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onActivated?(self.route, self.pane)
        }
    }
}

struct AppRouteActivationSentinel: NSViewRepresentable {
    var route: SidebarItem
    var pane: AppRoutePane
    var tracker: AppRoutePerformanceTracker

    func makeNSView(context: Context) -> AppRouteActivationNSView {
        let view = AppRouteActivationNSView(frame: .zero)
        view.onActivated = { [weak tracker] route, pane in
            tracker?.markPresented(route: route, pane: pane)
        }
        view.update(route: route, pane: pane)
        return view
    }

    func updateNSView(_ nsView: AppRouteActivationNSView, context: Context) {
        nsView.onActivated = { [weak tracker] route, pane in
            tracker?.markPresented(route: route, pane: pane)
        }
        nsView.update(route: route, pane: pane)
    }
}
