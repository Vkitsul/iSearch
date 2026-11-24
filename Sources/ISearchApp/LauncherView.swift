import AppKit
import ISearchCore
import SwiftUI

struct LauncherView: View {
    @Bindable var model: LauncherModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !model.sections.isEmpty {
                Divider()
                resultList
                Divider()
                footer
            }
        }
        .frame(width: LauncherLayout.width, height: model.panelHeight)
        .background(PanelBackground())
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: model.presentationCount) { fieldFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search apps, projects and settings, or ask Claude", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .light))
                .focused($fieldFocused)
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.barHeight)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(indexedSections, id: \.section.id) { entry in
                        Text(entry.section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: LauncherLayout.sectionHeaderHeight, alignment: .bottomLeading)

                        ForEach(Array(entry.section.rows.enumerated()), id: \.element.id) { position, row in
                            let index = entry.firstIndex + position
                            ResultRowView(row: row, isSelected: index == model.selection, home: model.home)
                                .id(index)
                                .contentShape(.rect)
                                .onTapGesture { model.run(row) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, LauncherLayout.listPadding / 2)
            }
            .scrollIndicators(.never)
            .frame(height: model.listHeight)
            .onChange(of: model.selection) { _, selection in
                proxy.scrollTo(selection)
            }
        }
    }

    private var indexedSections: [(section: ResultSection, firstIndex: Int)] {
        var next = 0
        return model.sections.map { section in
            defer { next += section.rows.count }
            return (section, next)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(selectionHints, id: \.self) { KeyHint(text: $0) }
            Spacer()
            KeyHint(text: "⌘↵ Ask Claude")
            KeyHint(text: "⌥↵ Incognito")
        }
        .padding(.horizontal, 16)
        .frame(height: LauncherLayout.footerHeight)
    }

    private var selectionHints: [String] {
        switch model.selectedRow {
        case .item(let item):
            switch item.kind {
            case .app: ["↵ Open"]
            case .settingsPane, .setting: ["↵ Open in Settings"]
            case .project, .folder: ["↵ Open in Finder", "⇧↵ Claude Code here"]
            case .file: ["↵ Open", "⇧↵ Show in Finder"]
            }
        case .claude:
            ["↵ Open chat"]
        case nil:
            []
        }
    }
}

private struct KeyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

private struct ResultRowView: View {
    let row: ResultRow
    let isSelected: Bool
    let home: String

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(row: row)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            if let shortcut {
                KeyHint(text: shortcut)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherLayout.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.1))
            }
        }
    }

    private var title: String {
        switch row {
        case .item(let item): item.title
        case .claude(let prompt, _): prompt
        }
    }

    private var subtitle: String? {
        switch row {
        case .item(let item):
            item.kind == .app ? nil : item.location(home: home)
        case .claude(_, let incognito):
            incognito ? "New incognito chat, in your browser" : "New chat in the Claude app"
        }
    }

    private var shortcut: String? {
        guard case .claude(_, let incognito) = row else { return nil }
        return incognito ? "⌥↵" : "⌘↵"
    }
}

private struct RowIcon: View {
    let row: ResultRow

    var body: some View {
        switch row {
        case .item(let item):
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.iconPath))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .claude(_, let incognito):
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(incognito ? Color.secondary.opacity(0.35) : Color.orange.opacity(0.85))
                Image(systemName: incognito ? "eye.slash.fill" : "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(2)
        }
    }
}

/// `.active` keeps the blur on even though the app itself never becomes frontmost.
private struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
