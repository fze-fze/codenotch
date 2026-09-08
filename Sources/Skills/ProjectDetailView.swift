import SwiftUI

struct ProjectDetailView: View {
    let project: SkillProject
    @ObservedObject var model: SkillManagerModel
    @State private var pickingMark = false
    @State private var query = SkillSearchQuery()
    @State private var activeOnly = false
    @State private var opened: SkillsSheet?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        // The mark is its own control. Nothing else on the page
                        // changes it, and a separate "Icon…" button would be a
                        // row spent pointing at something already on screen.
                        ProjectMarkButton(mark: project.mark) { pickingMark = true }
                        .help("Change the icon and colour")
                        .popover(isPresented: $pickingMark, arrowEdge: .bottom) {
                            ProjectMarkPicker(mark: project.mark) {
                                model.setMark($0, project: project)
                            }
                        }

                        Text(project.name)
                            .font(PanelFont.title)
                        if project.isPinned {
                            Image(systemName: "pin.fill")
                                .font(PanelFont.note)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(project.displayPath(home: model.home))
                        .font(PanelFont.mono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 8) {
                        Button(project.isPinned ? "Unpin" : "Pin") {
                            model.setPinned(!project.isPinned, project: project)
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([project.url])
                        }
                        Button("Remove from list") { model.forgetProject(project) }
                            .help("Nothing in the folder is touched")
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack {
                    Picker("Show skills", selection: $activeOnly) {
                        Text("All skills").tag(false)
                        Text("Active & local").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    SkillTagFilter(tags: model.allTags, selection: $query.tags)
                    if !query.isEmpty {
                        Button("Clear") { query = SkillSearchQuery() }
                    }
                }
                if !query.tags.isEmpty {
                    FlowLayout {
                        ForEach(query.tags.sorted(), id: \.self) { tag in
                            TagChip(tag: tag, onRemove: { query.tags.remove(tag) })
                        }
                    }
                }
            }

            ProjectSkillList(project: project, model: model, query: query, activeOnly: activeOnly) {
                opened = .library($0)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $opened) { sheet in
            SkillSheet(sheet: sheet, model: model) { opened = nil }
        }
    }

}
