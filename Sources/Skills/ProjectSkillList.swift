import SwiftUI

/// Four explicit groups distinguish local selection from inherited availability.
struct ProjectSkillList: View {
    let project: SkillProject
    @ObservedObject var model: SkillManagerModel
    let query: SkillSearchQuery
    let activeOnly: Bool
    let open: (String) -> Void

    private var matching: [StoredSkill] {
        model.storeSkills.filter {
            query.matches(name: $0.name, displayName: $0.displayName, summary: $0.summary,
                          tags: model.tags(for: $0.name, declared: $0.frontmatter.tags))
        }
    }

    private var local: [ProjectSkill] {
        let managedNames = Set(model.storeSkills.map(\.name))
        return (model.projectSkills[project.id] ?? []).filter {
            // A conflicting local item appears beside its managed counterpart,
            // rather than twice in two apparently independent lists.
            !managedNames.contains($0.name)
            && query.matches(name: $0.name, displayName: $0.displayName, summary: $0.summary,
                             tags: model.tags(for: $0.name, declared: $0.frontmatter.tags))
        }
    }

    var body: some View {
        let skills = matching
        let linked = skills.filter { model.reach(of: $0, in: project) == .linked }
        let global = skills.filter { model.reach(of: $0, in: project) == .everywhere }
        let available = skills.filter { model.reach(of: $0, in: project) == .absent }
        let blocked = skills.filter { if case .blocked = model.reach(of: $0, in: project) { return true }; return false }
        let localSkills = local
        if !linked.isEmpty {
            Section("Active in this project · \(linked.count)") {
                ForEach(linked) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        if !global.isEmpty {
            Section("Inherited from Global · \(global.count)") {
                ForEach(global) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        if !localSkills.isEmpty {
            Section("Local to this project · \(localSkills.count)") {
                ForEach(localSkills) { skill in ProjectLocalSkillRow(skill: skill) }
            }
        }
        if !blocked.isEmpty {
            Section("Local overrides · \(blocked.count)") {
                ForEach(blocked) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        if !activeOnly && !available.isEmpty {
            Section("Available from Library · \(available.count)") {
                ForEach(available) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        if linked.isEmpty && global.isEmpty && localSkills.isEmpty && blocked.isEmpty && (activeOnly || available.isEmpty) {
            ContentUnavailableView {
                Label(query.isEmpty ? "No active skills" : "No matching skills", systemImage: "square.stack.3d.up")
            } description: {
                Text(query.isEmpty ? "Choose All skills to add skills from Library." : "Try another search or remove a tag filter.")
            }
        }
    }
}
