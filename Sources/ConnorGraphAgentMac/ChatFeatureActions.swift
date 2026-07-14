import Foundation

@MainActor
final class ChatFeatureActions {
    unowned let orchestration: AppViewModel
    init(orchestration: AppViewModel) { self.orchestration = orchestration }
}
