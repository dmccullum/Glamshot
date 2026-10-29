import AppKit
import GlamshotCore
import SwiftUI

/// The file name template as a token field: Domain, Page Title and the rest are chips, and
/// anything typed between them is plain text. The template itself is stored as “{domain} — {size}”.
struct FileNameField: NSViewRepresentable {
    @Binding var template: String

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        // Nothing typed turns into a chip; chips come from the buttons below or a drag.
        field.tokenizingCharacterSet = CharacterSet()
        field.completionDelay = .greatestFiniteMagnitude
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("File Name")
        field.objectValue = Coordinator.objects(for: template)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.template = $template
        if Coordinator.template(from: field.objectValue) != template, field.currentEditor() == nil {
            field.objectValue = Coordinator.objects(for: template)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(template: $template) }

    /// A chip in the field.
    final class TokenObject: NSObject {
        let token: FileNaming.Token
        init(_ token: FileNaming.Token) { self.token = token }
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var template: Binding<String>

        init(template: Binding<String>) { self.template = template }

        static func objects(for template: String) -> [Any] {
            FileNaming.parts(of: template).map { part -> Any in
                switch part {
                case .text(let text): text
                case .token(let token): TokenObject(token)
                }
            }
        }

        static func template(from value: Any?) -> String {
            let objects = value as? [Any] ?? []
            return FileNaming.template(from: objects.compactMap { object in
                if let token = object as? TokenObject { return .token(token.token) }
                if let text = object as? String { return .text(text) }
                return nil
            })
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            template.wrappedValue = Self.template(from: field.objectValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTokenField else { return }
            // Typed “{date}” becomes a chip once editing ends.
            let value = Self.template(from: field.objectValue)
            template.wrappedValue = value
            field.objectValue = Self.objects(for: value)
        }

        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
            representedObject is TokenObject ? .rounded : .none
        }

        func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
            (representedObject as? TokenObject)?.token.title ?? representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
            (representedObject as? TokenObject)?.token.placeholder ?? representedObject as? String
        }

        func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
            FileNaming.Token.allCases.first { $0.placeholder == editingString }.map(TokenObject.init) ?? editingString
        }

        // Copy and drag as template text, so chips paste back as chips.
        func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
            pboard.clearContents()
            return pboard.setString(Self.template(from: objects), forType: .string)
        }

        func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
            pboard.string(forType: .string).map(Self.objects(for:))
        }
    }
}

/// The settings row: the field, a chip for each token to insert or drag in, and the name it makes.
struct FileNameSetting: View {
    @Binding var template: String

    private var example: String {
        FileNaming.name(template, FileNaming.Context(
            url: URL(string: "https://www.apple.com/mac/"), title: "Mac - Apple", sizeName: "MacBook Pro 14\"",
            width: 3024, height: 1964, frameName: "Safari on Canvas"
        ))
    }

    var body: some View {
        LabeledContent("File Name") {
            FileNameField(template: $template)
                .frame(minWidth: 220)
        }
        LabeledContent("Insert") {
            FlowLayout(spacing: 6) {
                ForEach(FileNaming.Token.allCases, id: \.self) { token in
                    Button(token.title) { insert(token) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .buttonBorderShape(.capsule)
                        .draggable(token.placeholder)
                        .help("Adds “\(token.title)” to the end of the name; drag it to put it elsewhere")
                }
            }
        }
        LabeledContent("Example") {
            Text(example)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    /// Adds a token at the end, with a space before it unless the name already ends in one or in
    /// a separator.
    private func insert(_ token: FileNaming.Token) {
        if let last = template.last, !last.isWhitespace, !"-_—–(.".contains(last) { template += " " }
        template += token.placeholder
    }
}

/// Lays chips out in rows, wrapping to the width it's given.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            // Right-aligned, like the other controls in a grouped form.
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if added > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width = added
                rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            }
        }
        return rows
    }
}
