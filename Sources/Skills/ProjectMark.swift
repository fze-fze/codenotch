import SwiftUI

/// The icon and colour a project is recognised by.
///
/// A list of folder names is a list of words to read; a list of marks is
/// something you find with your eyes. That is the whole justification, and it
/// is why the choice is the user's: only they know which of their projects is
/// "the blue hammer one".
///
/// Both halves are stored as **names**, not as a `Color` or an `Image`. A
/// colour serialised as components stops matching the system palette the moment
/// macOS adjusts one, and an SF Symbol is only ever a name anyway.
struct ProjectMark: Equatable, Sendable, Codable {
    var symbol: String
    var color: String

    static let fallback = ProjectMark(symbol: "folder", color: "graphite")

    /// Deliberately short. A palette of forty symbols is a search problem; a
    /// dozen is a glance. These cover what a project usually *is* — code, a
    /// document, a picture, a site, a tool — rather than trying to be a
    /// complete iconography.
    static let symbols = [
        "folder", "hammer.fill", "chevron.left.forwardslash.chevron.right",
        "paintbrush.fill", "doc.text.fill", "book.closed.fill",
        "globe", "terminal.fill", "shippingbox.fill",
        "sparkles", "camera.fill", "leaf.fill"
    ]

    /// System colours, so they stay right in both appearances and shift with
    /// the user's accent settings the way the rest of macOS does.
    static let palette: [(name: String, color: Color)] = [
        ("graphite", .secondary),
        ("blue", .blue),
        ("teal", .teal),
        ("green", .green),
        ("yellow", .yellow),
        ("orange", .orange),
        ("red", .red),
        ("pink", .pink),
        ("purple", .purple),
        ("indigo", .indigo)
    ]

    var swiftUIColor: Color {
        Self.palette.first { $0.name == color }?.color ?? .secondary
    }
}

/// A project's mark at a given size.
struct ProjectMarkView: View {
    let mark: ProjectMark
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: mark.symbol)
            .font(.system(size: size))
            .foregroundStyle(mark.swiftUIColor)
            // A fixed box so a wide symbol and a narrow one leave their rows
            // the same shape — otherwise every name in the sidebar starts at a
            // slightly different x.
            .frame(width: size * 1.5, alignment: .center)
    }
}

/// The mark as a *control*: the same icon, but visibly something to press.
///
/// It was not, and nobody found it. An icon at the top of a page reads as
/// decoration however good the tooltip is, so this one wears a well on hover
/// and carries a small chevron — the two things macOS uses everywhere else to
/// say "there is a menu under here".
struct ProjectMarkButton: View {
    let mark: ProjectMark
    var size: CGFloat = 26
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                ProjectMarkView(mark: mark, size: size)
                Image(systemName: "chevron.down")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.045))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The picker behind a project's mark: a row of colours, a grid of symbols.
///
/// Small enough to be a popover rather than a sheet, because choosing an icon
/// is a decision worth about a second and a sheet costs two clicks to leave.
struct ProjectMarkPicker: View {
    /// Held locally and written out on each change, rather than driven by a
    /// binding back through the model. Every write goes through a rescan of
    /// every project, and reading the *old* value back in the moment between
    /// picking a colour and picking a symbol would drop the colour.
    @State private var mark: ProjectMark
    private let onChange: (ProjectMark) -> Void

    init(mark: ProjectMark, onChange: @escaping (ProjectMark) -> Void) {
        _mark = State(initialValue: mark)
        self.onChange = onChange
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(ProjectMark.palette, id: \.name) { entry in
                    Button {
                        mark.color = entry.name
                        onChange(mark)
                    } label: {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.5), lineWidth: 2)
                                    .opacity(mark.color == entry.name ? 1 : 0)
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ProjectMark.symbols, id: \.self) { symbol in
                    Button {
                        mark.symbol = symbol
                        onChange(mark)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(mark.symbol == symbol
                                             ? mark.swiftUIColor : Color.secondary)
                            .frame(width: 30, height: 26)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(mark.symbol == symbol ? 0.1 : 0))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }
}
