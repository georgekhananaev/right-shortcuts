import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case menu
    case templates
    case locations
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .menu: "Menu Items"
        case .templates: "New File"
        case .locations: "Folders"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "house.fill"
        case .menu: "contextualmenu.and.cursorarrow"
        case .templates: "doc.badge.plus"
        case .locations: "folder.fill"
        case .general: "gearshape.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .brand
        case .menu: .blue
        case .templates: .orange
        case .locations: .teal
        case .general: .gray
        case .about: .indigo
        }
    }
}

/// The settings window: a sidebar of panes and the selected pane.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        IconTile(symbol: pane.symbol, color: pane.tint, size: 20)
                    }
                    .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .frame(minHeight: 0, idealHeight: 300, maxHeight: .infinity)
        } detail: {
            // A small ideal height keeps long panes from stretching the split view past the window.
            detail
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, idealHeight: 300, maxHeight: .infinity,
                       alignment: .topLeading)
        }
        .hidingToolbarTitle()
        .tint(.brand)
    }

    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { model.selectedPane },
            set: { if let pane = $0 { model.selectedPane = pane } }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedPane {
        case .overview: OverviewPane()
        case .menu: MenuItemsPane()
        case .templates: TemplatesPane()
        case .locations: LocationsPane()
        case .general: GeneralPane()
        case .about: AboutPane()
        }
    }
}

private extension View {
    /// Each pane shows its own title, so the toolbar doesn't repeat the app name (macOS 15 and later).
    @ViewBuilder
    func hidingToolbarTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}
