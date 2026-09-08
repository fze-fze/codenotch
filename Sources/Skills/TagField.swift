import SwiftUI

struct TagField: View {
    @Binding var text: String
    let commit: () -> Void

    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $text, prompt: Text("tag").foregroundStyle(.tertiary))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .focused($focused)
                        .frame(width: 120)
                        .accessibilityLabel("New tag")
                        .onExitCommand { text = ""; editing = false }
                        .onSubmit {
                            commit()
                            editing = false
                        }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background { Capsule().fill(Color.primary.opacity(0.1)) }
                .overlay { Capsule().strokeBorder(Color.accentColor.opacity(0.8)) }
                // Focus is asked for here rather than at build time, so it
                // happens because the button was pressed and never because a
                // sheet appeared.
                .onAppear { focused = true }
                .onChange(of: focused) { _, isFocused in
                    // Clicking away from an empty field puts the plus back.
                    if !isFocused, text.isEmpty { editing = false }
                }
            } else {
                Button {
                    editing = true
                } label: {
                    Label("Add tag", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Color.primary.opacity(0.06)) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Add a tag")
            }
        }
        .font(.system(size: 12))
    }
}
