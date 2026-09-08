import SwiftUI

struct SkillTagFilter: View {
    let tags: [String]
    @Binding var selection: Set<String>
    @State private var isPresented = false
    @State private var search = ""

    private var filtered: [String] {
        Array(Set(tags).union(selection)).sorted().filter {
            search.isEmpty || $0.localizedStandardContains(search)
        }
    }

    var body: some View {
        Button(selection.isEmpty ? "Tags" : "Tags · \(selection.count)", systemImage: "tag") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Filter by tags").font(.headline)
                    Spacer()
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }
                SkillSearchField(prompt: "Find a tag", text: $search)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered, id: \.self) { tag in
                            Button { toggle(tag) } label: {
                                HStack {
                                    Text(tag).lineLimit(2)
                                    Spacer()
                                    Image(systemName: selection.contains(tag) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selection.contains(tag) ? Color.accentColor : .secondary)
                                }
                                .padding(6)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(selection.contains(tag) ? "Selected" : "Not selected")
                        }
                        if filtered.isEmpty {
                            Text(tags.isEmpty ? "Add tags in a skill’s details." : "No matching tags")
                                .foregroundStyle(.secondary)
                                .padding(.vertical)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 280, height: 340)
        }
    }

    private func toggle(_ tag: String) {
        if selection.contains(tag) { selection.remove(tag) }
        else { selection.insert(tag) }
    }
}
