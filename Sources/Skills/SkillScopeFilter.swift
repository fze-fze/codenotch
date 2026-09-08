import Foundation

enum SkillScopeFilter: Hashable {
    case all, global, projects, unassigned
    case project(String)

    func matches(isGlobal: Bool, linkedProjects: Set<String>, activeProjects: Set<String>) -> Bool {
        switch self {
        case .all: return true
        case .global: return isGlobal
        case .projects: return !linkedProjects.isEmpty
        case .unassigned: return !isGlobal && linkedProjects.isEmpty
        case .project(let id): return activeProjects.contains(id)
        }
    }
}
