import AppKit
import SwiftUI

/// The existing card catalog, with independent filters for source and scope.
struct SkillsPageView: View {
    @ObservedObject var model: SkillManagerModel
    @State private var query = SkillSearchQuery()
    @State private var category = SkillCategoryFilter.all
    @State private var scope = SkillScopeFilter.all
    @State private var opened: SkillsSheet?

    var body: some View {
        let library = filteredLibrary
        let agentOnly = filteredAgentSkills
        VStack(spacing: 0) {
            SkillsFilterBar(query: $query, category: $category, scope: $scope,
                            tags: model.allTags, projects: model.projects,
                            count: library.count + agentOnly.count,
                            isRefreshing: model.isRefreshing, refresh: model.refresh)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !library.isEmpty {
                        SkillCatalogSection(title: "Library", subtitle: "Managed skills", count: library.count) {
                            ForEach(library) { skill in
                                LibraryCard(skill: skill, model: model, filterTag: selectTag) {
                                    opened = .library(skill.id)
                                }
                            }
                        }
                    }
                    if !agentOnly.isEmpty {
                        SkillCatalogSection(title: "Agent-only", subtitle: "In an agent’s own folder", count: agentOnly.count) {
                            ForEach(agentOnly) { skill in
                                AgentCard(skill: skill, model: model, filterTag: selectTag) {
                                    opened = .agent(skill.id)
                                }
                            }
                        }
                    }
                    if library.isEmpty && agentOnly.isEmpty {
                        ContentUnavailableView {
                            Label(model.isRefreshing ? "Reading skills…" : isFiltering ? "No matching skills" : "No skills yet",
                                  systemImage: isFiltering ? "magnifyingglass" : "square.stack.3d.up")
                        } description: {
                            Text(isFiltering ? "Try another search, tag, or scope." : "Skills from your installed agents will appear here.")
                        } actions: {
                            if isFiltering { Button("Clear filters", action: clearFilters) }
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(20)
            }
        }
        .font(PanelFont.row)
        .sheet(item: $opened) { sheet in
            SkillSheet(sheet: sheet, model: model) { opened = nil }
        }
        .alert("Couldn’t complete the change",
               isPresented: Binding(get: { model.problem != nil },
                                    set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: { Text(model.problem ?? "") }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
    }

    private var isFiltering: Bool { !query.isEmpty || category != .all || scope != .all }

    private var filteredLibrary: [StoredSkill] {
        guard category != .agentOnly else { return [] }
        return model.storeSkills.filter { skill in
            scope.matches(isGlobal: skill.isGlobal, linkedProjects: Set(model.projectsUsing(skill.name)),
                          activeProjects: Set(model.projects.filter { model.reach(of: skill, in: $0).isReachable }.map(\.id)))
            && query.matches(name: skill.name, displayName: skill.displayName, summary: skill.summary,
                             tags: model.tags(for: skill.name, declared: skill.frontmatter.tags))
        }
    }

    private var filteredAgentSkills: [AgentSkill] {
        guard category != .library, scope == .all else { return [] }
        return model.agents.flatMap { model.agentSkills[$0] ?? [] }.filter { skill in
            query.matches(name: skill.name, displayName: skill.displayName, summary: skill.summary,
                          tags: model.tags(for: skill.name, declared: skill.frontmatter.tags))
        }
    }

    private func selectTag(_ tag: String) { query.tags.insert(tag) }

    private func clearFilters() {
        query = SkillSearchQuery()
        category = .all
        scope = .all
    }
}
