import SwiftUI

struct LibraryDetailView: View {
    let skill: StoredSkill
    @ObservedObject var model: SkillManagerModel
    let close: () -> Void
    @State private var confirmingDelete = false
    @State private var projectSearch = ""

    /// The real folder, with `~` back in it — how anybody actually reads it.
    private var path: String {
        let full = skill.url.standardizedFileURL.path
        let base = model.home.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? "~" + full.dropFirst(base.count) : full
    }

    private var filteredProjects: [SkillProject] {
        model.projects.filter {
            projectSearch.isEmpty || $0.name.localizedStandardContains(projectSearch)
                || $0.displayPath(home: model.home).localizedStandardContains(projectSearch)
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(skill.displayName)
                        .font(PanelFont.title)

                    Label("Library", systemImage: "square.stack.3d.up")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                    Text(path)
                        .font(PanelFont.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let summary = skill.summary {
                        ExpandableText(text: summary)
                            .font(PanelFont.note)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([skill.url])
                        }
                        Button("Remove…") { confirmingDelete = true }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            Section("Tags") {
                TagEditor(name: skill.name,
                          declared: skill.frontmatter.tags,
                          model: model)
            }

            Section("Scope") {
                Toggle("Global · available across projects", isOn: Binding(
                    get: { skill.isGlobal },
                    set: { model.setGlobal($0, skill: skill.name) }
                ))
                .toggleStyle(.switch)
                .help("Links it into ~/.agents/skills — the folder does not move")

                if !skill.shadowedBy.isEmpty {
                    Label("Another folder of this name is shadowing it — rename one",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(PanelFont.note)
                        .foregroundStyle(.orange)
                        .help(skill.shadowedBy.map(\.path).joined(separator: "\n"))
                }
            }

            Section("Projects · \(model.projectsUsing(skill.name).count) linked") {
                if model.projects.count > 4 {
                    SkillSearchField(prompt: "Find a project", text: $projectSearch)
                }
                ForEach(filteredProjects) { project in
                    SkillProjectScopeRow(project: project, skill: skill, model: model)
                }
                if model.projects.isEmpty {
                    Text("Add a folder in Projects first")
                        .font(PanelFont.note).foregroundStyle(.secondary)
                } else if filteredProjects.isEmpty {
                    Text("No matching projects").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove \(skill.name)?",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                model.delete(skill.name)
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlinked everywhere, then moved to the Trash.")
        }
    }
}
