import Foundation

enum SkillCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All skills"
    case library = "Library"
    case agentOnly = "Agent-only"

    var id: Self { self }
}
