import AppKit
import SwiftUI

/// The folders you work in, and what their agents read there.
///
/// The unit that matters. A skill in a project costs context in that project
/// and nowhere else, which is the whole reason this page exists: the
/// alternative is `~/.agents/skills`, read by three of the four agents in every
/// session of every project, asked for or not.
///
/// Projects are remembered, not discovered. Walking the disk for `.git` and
/// guessing which results are "projects" is how a sidebar fills with
/// `node_modules`.
struct ProjectsPageView: View {
    @ObservedObject var model: SkillManagerModel
    @State private var selection: String?
    @State private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(PanelFont.row)
        .alert("Couldn’t complete the change",
               isPresented: Binding(get: { model.problem != nil },
                                    set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
        .onAppear { model.refresh(); selectFirstProjectIfNeeded() }
        .onChange(of: model.projects.map(\.id)) { selectFirstProjectIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification
        )) { _ in model.refresh() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            SkillSearchField(prompt: "Find a project", text: $search)
                .padding(10)
            List(selection: $selection) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { project in
                            ProjectRow(project: project, model: model).tag(project.id)
                        }
                    }
                }
                Section(pinned.isEmpty ? "Projects" : "All") {
                    ForEach(rest) { project in
                        ProjectRow(project: project, model: model).tag(project.id)
                    }
                    if rest.isEmpty && pinned.isEmpty {
                        Text(search.isEmpty ? "No projects yet" : "No matching projects")
                            .font(PanelFont.note)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Button("Add project", systemImage: "plus", action: addProject)
                    .labelStyle(.iconOnly)
                    .help("Add a project folder")
                Button("Refresh projects", systemImage: "arrow.clockwise", action: model.refresh)
                    .labelStyle(.iconOnly)
                    .help("Re-read skills and projects")
                Spacer(minLength: 4)
                Text("\(model.projects.count)")
                    .font(PanelFont.note)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    private var matchingProjects: [SkillProject] {
        model.projects.filter {
            search.isEmpty || $0.name.localizedStandardContains(search)
                || $0.displayPath(home: model.home).localizedStandardContains(search)
        }
    }

    private func selectFirstProjectIfNeeded() {
        if selection == nil || !model.projects.contains(where: { $0.id == selection }) {
            selection = model.projects.first(where: \.isPinned)?.id ?? model.projects.first?.id
        }
    }

    private var pinned: [SkillProject] { matchingProjects.filter(\.isPinned) }
    private var rest: [SkillProject] { matchingProjects.filter { !$0.isPinned } }

    private func addProject() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "Add"
        openPanel.message = "Choose the project folders to manage."
        guard openPanel.runModal() == .OK else { return }
        for url in openPanel.urls { model.addProject(url) }
        selection = openPanel.urls.last.map { SkillProject(url: $0).id }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let project = model.projects.first(where: { $0.id == selection }) {
            ProjectDetailView(project: project, model: model).id(project.id)
        } else if model.projects.isEmpty {
            VStack(spacing: 10) {
                Text("No projects yet")
                    .foregroundStyle(.secondary)
                Button("Add a project…") { addProject() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Select a project")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

