import SwiftUI

struct SkillsFilterBar: View {
    @Binding var query: SkillSearchQuery
    @Binding var category: SkillCategoryFilter
    @Binding var scope: SkillScopeFilter
    let tags: [String]
    let projects: [SkillProject]
    let count: Int
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                SkillSearchField(prompt: "Search skills or #tags", text: $query.text)
                    .frame(maxWidth: 320)
                Spacer(minLength: 0)
                Picker("Category", selection: $category) {
                    ForEach(SkillCategoryFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            HStack(spacing: 10) {
                Picker("Scope", selection: $scope) {
                    Text("All scopes").tag(SkillScopeFilter.all)
                    Text("Global").tag(SkillScopeFilter.global)
                    Text("Linked to projects").tag(SkillScopeFilter.projects)
                    Text("No shared scope").tag(SkillScopeFilter.unassigned)
                    if !projects.isEmpty {
                        Divider()
                        ForEach(projects) { project in
                            Text(project.name).tag(SkillScopeFilter.project(project.id))
                        }
                    }
                }
                .frame(maxWidth: 245)
                .disabled(category == .agentOnly)
                SkillTagFilter(tags: tags, selection: $query.tags)
                if !query.isEmpty || category != .all || scope != .all {
                    Button("Clear filters", action: clear)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("^[\(count) skill](inflect: true)")
                    .font(PanelFont.note)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Refresh skills", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly)
                    .disabled(isRefreshing)
                    .help("Re-read skills and projects")
            }
            if !query.tags.isEmpty {
                FlowLayout {
                    ForEach(query.tags.sorted(), id: \.self) { tag in
                        TagChip(tag: tag, onRemove: { query.tags.remove(tag) })
                    }
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onChange(of: category) { _, value in
            if value == .agentOnly { scope = .all }
        }
    }

    private func clear() {
        query = SkillSearchQuery()
        category = .all
        scope = .all
    }
}
