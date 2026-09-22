import Combine
import TokcatKit

/// Task views observe this store, not the menu-bar animation's 0.4-second updates.
@MainActor
final class TaskMonitorStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var tasks: [AgentTaskRecord] = []
    @Published private(set) var enabledSources: Set<AgentSource> = AgentSource.defaultEnabled

    func update(sessions: [AgentSession], tasks: [AgentTaskRecord], enabled: Set<AgentSource>) {
        let visibleSessions = sessions.filter { enabled.contains($0.source) }
        let visibleTasks = tasks.filter { enabled.contains($0.session.source) }
        if self.sessions != visibleSessions { self.sessions = visibleSessions }
        if self.tasks != visibleTasks { self.tasks = visibleTasks }
        if enabledSources != enabled { enabledSources = enabled }
    }
}
