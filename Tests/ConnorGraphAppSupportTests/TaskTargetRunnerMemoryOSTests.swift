import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Test func taskTargetRunnerDispatchesMemoryOSPipelineTargets() async throws {
    let spy = MemoryOSPipelineSpy()
    let runner = TaskTargetRunner(
        mailRefresher: { _ in "mail" },
        calendarRefresher: { _ in "calendar" },
        rssRefresher: { _ in "rss" },
        sessionMessenger: { _ in "session" },
        memoryOSPipelineRunner: spy.run
    )
    let l1Task = ConnorTaskDefinition(
        id: "memory-os.plan-l1",
        name: "Plan L1 unified projection jobs",
        origin: .system,
        trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 300, recurrence: .interval),
        target: ConnorTaskTarget(targetKind: "memory_os.pipeline", targetID: "default", operationName: "plan_l1_unified_projection_jobs"),
        lifecycle: ConnorTaskLifecycle(status: .active),
        metadata: .protectedSystem
    )


    let l1Result = try await runner.run(task: l1Task, runID: "run-l1")

    #expect(l1Result.summary == "memory plan_l1_unified_projection_jobs")
    #expect(await spy.requests == [
        MemoryOSPipelineTaskRequest(operationName: "plan_l1_unified_projection_jobs", runID: "run-l1")
    ])
}

private actor MemoryOSPipelineSpy {
    var requests: [MemoryOSPipelineTaskRequest] = []
    func run(_ request: MemoryOSPipelineTaskRequest) async throws -> String {
        requests.append(request)
        return "memory \(request.operationName)"
    }
}
