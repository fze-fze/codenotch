import SwiftUI

/// Two groups, because there are only two answers to "why can this project see
/// this skill": it is loaded everywhere, or this project chose it.
///
/// It was three. "Active in this project" and "Available from Library" listed
/// the same skills from the same place, split by which way their own switch was
/// pointing — so turning one on made the row *jump to a different section*, and
/// "what can I put in here" had to be answered by reading two headings that
/// were pages apart. One list, with the ones that are on at the top, answers
/// both questions and holds still while you use it.
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
        let groups = ProjectSkillGroups(
            skills: matching, activeOnly: activeOnly
        ) { model.reach(of: $0, in: project) }
        let global = groups.global
        let library = groups.library
        let localSkills = local

        if !global.isEmpty {
            Section("Global · \(global.count)") {
                ForEach(global) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        if !library.isEmpty {
            Section("From Library · \(library.count)") {
                ForEach(library) { skill in
                    ProjectSkillRow(project: project, skill: skill, model: model) { open(skill.id) }
                }
            }
        }
        // Kept, and kept apart, though it is neither of the two: these are real
        // folders the project owns and Codenotch did not put there. They are
        // not offered from anywhere and there is no switch to give them, so
        // filing them under "From Library" would be a lie about where they came
        // from. The section is absent entirely unless the project has some.
        if !localSkills.isEmpty {
            Section("Local to this project · \(localSkills.count)") {
                ForEach(localSkills) { skill in ProjectLocalSkillRow(skill: skill) }
            }
        }
        if global.isEmpty && library.isEmpty && localSkills.isEmpty {
            ContentUnavailableView {
                Label(query.isEmpty ? "No active skills" : "No matching skills",
                      systemImage: "square.stack.3d.up")
            } description: {
                Text(query.isEmpty
                     ? "Choose All skills to add skills from Library."
                     : "Try another search or remove a tag filter.")
            }
        }
    }
}

/// Which of the two groups each skill falls into, worked out away from the
/// view so it can be checked without building one.
///
/// The ordering is the part worth pinning down. A `Form` renders what it is
/// handed, so "on ones first" is not a property of the UI — it is a property of
/// this array, and nothing on screen would look wrong if it quietly stopped
/// holding.
struct ProjectSkillGroups {
    /// Loaded in every session. The project has these whatever it links, so
    /// there is no switch to offer and nothing to decide.
    let global: [StoredSkill]
    /// Everything this project's own switch decides, on ones first.
    let library: [StoredSkill]

    init(skills: [StoredSkill], activeOnly: Bool,
         reach: (StoredSkill) -> SkillManagerModel.ProjectReach) {
        // Partitioned by filtering rather than by sorting on a rank: Swift's
        // `sorted(by:)` is not a stable sort, and the store's order is what
        // puts these in alphabetical order to begin with. Separate passes keep
        // that order inside each group; one comparator would scramble it.
        global = skills.filter { reach($0) == .everywhere }
        let on = skills.filter { reach($0) == .linked }
        let blocked = skills.filter {
            if case .blocked = reach($0) { return true }
            return false
        }
        let off = skills.filter { reach($0) == .absent }

        // On first: "what is switched on in this project" is the question the
        // page exists to answer. Conflicts next, because they read as off and
        // are not — a skill the project's own folder is overriding, buried
        // under thirty available ones, is a skill nobody notices is broken.
        library = activeOnly ? on + blocked : on + blocked + off
    }
}
