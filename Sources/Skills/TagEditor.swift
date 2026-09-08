import SwiftUI

struct TagEditor: View {
    let name: String
    let declared: [String]
    @ObservedObject var model: SkillManagerModel
    @State private var typed = ""

    private var authorTags: [String] { Array(Set(declared)).sorted() }
    private var personalTags: [String] { model.ownTags(for: name).filter { !declared.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !authorTags.isEmpty {
                Text("From SKILL.md").font(.callout).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(authorTags, id: \.self) { tag in TagChip(tag: tag) }
                }
            }
            Text("Your tags").font(.callout).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(personalTags, id: \.self) { tag in
                    TagChip(tag: tag, onRemove: { model.removeTag(tag, from: name) })
                }
                TagField(text: $typed, commit: commit)
            }
        }
        .padding(.vertical, 2)
    }

    private func commit() {
        let tag = SkillTags.normalise(typed)
        if !tag.isEmpty && !declared.contains(tag) { model.addTag(tag, to: name) }
        typed = ""
    }
}
