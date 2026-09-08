import SwiftUI

struct AgentSkillDetailView: View {
    let skill: AgentSkill
    @ObservedObject var model: SkillManagerModel
    let willPromote: (String) -> Void
    @State private var promoting = false

    private var path: String {
        let full = skill.url.standardizedFileURL.path
        let base = model.home.standardizedFileURL.path
        return full.hasPrefix(base + "/") ? "~" + full.dropFirst(base.count) : full
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(skill.displayName)
                        .font(PanelFont.title)
                    Label("Agent-only · \(skill.agent.displayName)", systemImage: "person.crop.square")
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
                    // Beside Show in Finder, not in a section of its own. It
                    // was the only thing under a "Reach" heading whose other
                    // row said "Codex only" — a heading, a glyph and a line of
                    // text to hold one button, and the card behind this sheet
                    // already says which agent it belongs to.
                    HStack(spacing: 8) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([skill.url])
                        }
                        Button(promoting ? "Adding…" : "Add to Library") {
                            promoting = true
                            willPromote(skill.name)
                            model.promote([skill])
                        }
                            .disabled(skill.collidesWithLibrary || promoting)
                            .help("Moves the folder into the library and links it "
                                  + "back here — this agent keeps it")
                    }
                    .padding(.top, 2)

                    // Kept: taking it in on a collision would merge two
                    // different skills into whichever won, and the button is
                    // disabled with no other sign of why.
                    if skill.collidesWithLibrary {
                        Label("The library already has a different \(skill.name) — rename one",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(PanelFont.note)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Scope") {
                LabeledContent("Available to", value: skill.agent.displayName)
            }

            Section("Tags") {
                TagEditor(name: skill.name,
                          declared: skill.frontmatter.tags,
                          model: model)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.isRefreshing) { _, refreshing in
            guard promoting, !refreshing else { return }
            promoting = false

        }
    }
}
