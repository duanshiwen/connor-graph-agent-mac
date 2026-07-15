import AppKit
import SwiftUI
import ConnorGraphAppSupport

struct RetainedRouteCachePolicy: Sendable, Equatable {
    var retainedRoutes: Set<SidebarItem>
    var coldRouteLimit: Int

    static let sidebar = RetainedRouteCachePolicy(
        retainedRoutes: [.agentChat, .mail, .rss],
        coldRouteLimit: 1
    )

    func evictionCandidate(
        cachedRoutes: Set<SidebarItem>,
        coldRoutesByRecency: [SidebarItem],
        activating route: SidebarItem
    ) -> SidebarItem? {
        guard !retainedRoutes.contains(route), coldRouteLimit >= 0 else { return nil }
        let cachedColdRoutes = coldRoutesByRecency.filter {
            cachedRoutes.contains($0) && !retainedRoutes.contains($0) && $0 != route
        }
        guard cachedColdRoutes.count >= coldRouteLimit else { return nil }
        return cachedColdRoutes.first
    }
}

@MainActor
final class RetainedRouteHostController: NSViewController {
    typealias RouteFactory = @MainActor (SidebarItem) -> AnyView

    private let pane: AppRoutePane
    private let tracker: AppRoutePerformanceTracker
    private let policy: RetainedRouteCachePolicy
    private var contentOwner: ObjectIdentifier
    private var routeFactory: RouteFactory
    private var controllers: [SidebarItem: NSHostingController<AnyView>] = [:]
    private var coldRoutesByRecency: [SidebarItem] = []
    private(set) var activeRoute: SidebarItem?

    init(
        pane: AppRoutePane,
        tracker: AppRoutePerformanceTracker,
        policy: RetainedRouteCachePolicy = .sidebar,
        contentOwner: ObjectIdentifier,
        routeFactory: @escaping RouteFactory
    ) {
        self.pane = pane
        self.tracker = tracker
        self.policy = policy
        self.contentOwner = contentOwner
        self.routeFactory = routeFactory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container
    }

    var cachedRoutes: Set<SidebarItem> { Set(controllers.keys) }
    var cachedControllerCount: Int { controllers.count }
    var attachedControllerCount: Int {
        controllers.values.filter { $0.parent === self && $0.view.superview === view }.count
    }

    func controllerIdentity(for route: SidebarItem) -> ObjectIdentifier? {
        controllers[route].map(ObjectIdentifier.init)
    }

    func isRouteVisible(_ route: SidebarItem) -> Bool {
        controllers[route].map { !$0.view.isHidden && $0.view.superview === view } ?? false
    }

    func updateContent(
        owner: ObjectIdentifier,
        routeFactory: @escaping RouteFactory
    ) {
        self.routeFactory = routeFactory
        guard contentOwner != owner else { return }

        contentOwner = owner
        invalidateCachedRoutes()
        AppPerformanceLog.sidebarNavigationLogger.info(
            "sidebar.route.contentOwnerChanged pane=\(self.pane.rawValue, privacy: .public)"
        )
    }

    func activate(_ route: SidebarItem) {
        loadViewIfNeeded()
        if activeRoute == route, let controller = controllers[route] {
            installIfNeeded(controller)
            controller.view.isHidden = false
            tracker.markActivated(route: route, pane: pane, activationKind: .cacheHit)
            schedulePresented(route: route, controller: controller)
            return
        }

        let activationKind: AppRouteActivationKind
        let controller: NSHostingController<AnyView>
        if let cached = controllers[route] {
            activationKind = .cacheHit
            controller = cached
        } else {
            activationKind = .mount
            evictColdRouteIfNeeded(beforeActivating: route)
            let created = NSHostingController(rootView: routeFactory(route))
            controllers[route] = created
            controller = created
        }

        if let currentRoute = activeRoute,
           currentRoute != route,
           let current = controllers[currentRoute] {
            current.view.isHidden = true
        }

        installIfNeeded(controller)
        controller.view.isHidden = false
        view.addSubview(controller.view, positioned: .above, relativeTo: nil)
        activeRoute = route
        recordRecency(for: route)
        tracker.markActivated(route: route, pane: pane, activationKind: activationKind)
        schedulePresented(route: route, controller: controller)
    }

    private func schedulePresented(
        route: SidebarItem,
        controller: NSHostingController<AnyView>
    ) {
        controller.view.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self,
                  let controller,
                  self.activeRoute == route,
                  controller.view.superview === self.view,
                  !controller.view.isHidden
            else { return }
            self.tracker.markPresented(route: route, pane: self.pane)
        }
    }

    func evict(_ route: SidebarItem) {
        guard let controller = controllers.removeValue(forKey: route) else { return }
        if activeRoute == route { activeRoute = nil }
        coldRoutesByRecency.removeAll { $0 == route }
        detach(controller)
        AppPerformanceLog.sidebarNavigationLogger.debug(
            "sidebar.route.evicted route=\(route.rawValue, privacy: .public) pane=\(self.pane.rawValue, privacy: .public)"
        )
    }

    func shutdown() {
        invalidateCachedRoutes()
    }

    private func invalidateCachedRoutes() {
        for controller in controllers.values { detach(controller) }
        controllers.removeAll()
        coldRoutesByRecency.removeAll()
        activeRoute = nil
    }

    private func evictColdRouteIfNeeded(beforeActivating route: SidebarItem) {
        guard let candidate = policy.evictionCandidate(
            cachedRoutes: cachedRoutes,
            coldRoutesByRecency: coldRoutesByRecency,
            activating: route
        ) else { return }
        evict(candidate)
    }

    private func recordRecency(for route: SidebarItem) {
        guard !policy.retainedRoutes.contains(route) else { return }
        coldRoutesByRecency.removeAll { $0 == route }
        coldRoutesByRecency.append(route)
    }

    private func installIfNeeded(_ controller: NSHostingController<AnyView>) {
        guard controller.view.superview !== view else { return }
        if controller.parent !== self { addChild(controller) }
        let childView = controller.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        childView.isHidden = true
        view.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.topAnchor.constraint(equalTo: view.topAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func detach(_ controller: NSHostingController<AnyView>) {
        controller.view.removeFromSuperview()
        if controller.parent === self { controller.removeFromParent() }
    }
}

struct RetainedRouteHostView: NSViewControllerRepresentable {
    var route: SidebarItem
    var pane: AppRoutePane
    var tracker: AppRoutePerformanceTracker
    var policy: RetainedRouteCachePolicy = .sidebar
    var contentOwner: ObjectIdentifier
    var routeFactory: RetainedRouteHostController.RouteFactory

    func makeNSViewController(context: Context) -> RetainedRouteHostController {
        let controller = RetainedRouteHostController(
            pane: pane,
            tracker: tracker,
            policy: policy,
            contentOwner: contentOwner,
            routeFactory: routeFactory
        )
        controller.activate(route)
        return controller
    }

    func updateNSViewController(_ controller: RetainedRouteHostController, context: Context) {
        controller.updateContent(owner: contentOwner, routeFactory: routeFactory)
        controller.activate(route)
    }

    static func dismantleNSViewController(_ controller: RetainedRouteHostController, coordinator: Void) {
        controller.shutdown()
    }
}
