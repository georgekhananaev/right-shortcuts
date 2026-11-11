import Foundation
@testable import RightShortcutsCore
import Testing

@Suite("Menu resolver")
struct MenuResolverTests {
    private let file = SelectedItem(path: "/Users/me/Docs/report.pdf", isDirectory: false, isHidden: false)
    private let image = SelectedItem(path: "/Users/me/Docs/photo.JPG", isDirectory: false, isHidden: false)
    private let folder = SelectedItem(path: "/Users/me/Docs/Projects", isDirectory: true, isHidden: false)
    private let hiddenFile = SelectedItem(path: "/Users/me/Docs/.env", isDirectory: false, isHidden: true)

    private func items(_ selection: [SelectedItem]) -> MenuScenario {
        MenuScenario(location: .items, targetPath: "/Users/me/Docs", items: selection)
    }

    private func config(_ items: [MenuItem], layout: MenuLayout = .inline) -> AppConfig {
        var config = AppConfig()
        config.items = items
        config.menuLayout = layout
        return config
    }

    private func titles(_ nodes: [MenuNode]) -> [String] {
        nodes.map { $0.isSeparator ? "—" : $0.title }
    }

    @Test func fileOnlyItemsHideForFolders() {
        let item = MenuItem(kind: .builtin(action: .copyPath), contexts: [.files])
        #expect(MenuResolver.isVisible(item, in: items([file])))
        #expect(!MenuResolver.isVisible(item, in: items([folder])))
        #expect(!MenuResolver.isVisible(item, in: items([file, folder])))
    }

    @Test func disabledItemsNeverShow() {
        let item = MenuItem(kind: .builtin(action: .copyPath), isEnabled: false)
        #expect(!MenuResolver.isVisible(item, in: items([file])))
    }

    @Test func extensionFilterIsCaseInsensitiveAndIgnoresDots() {
        let item = MenuItem(kind: .builtin(action: .copyPath), fileExtensions: [" .jpg", "PNG"])
        #expect(MenuResolver.isVisible(item, in: items([image])))
        #expect(!MenuResolver.isVisible(item, in: items([file])))
        #expect(!MenuResolver.isVisible(item, in: items([image, file])))
        #expect(!MenuResolver.isVisible(item, in: items([folder])))
    }

    @Test func backgroundShowsOnlyItemsThatWorkWithoutSelection() {
        let background = MenuScenario(location: .container, targetPath: "/Users/me/Docs", items: [])
        #expect(MenuResolver.isVisible(.builtin(.newFile), in: background))
        #expect(MenuResolver.isVisible(.builtin(.copyPath), in: background))
        #expect(!MenuResolver.isVisible(.builtin(.hide), in: background))
        #expect(!MenuResolver.isVisible(MenuItem(kind: .builtin(action: .copyPath), contexts: [.files]), in: background))
    }

    @Test func toolbarWithoutSelectionSkipsSelectionActions() {
        let toolbar = MenuScenario(location: .toolbar, targetPath: "/Users/me/Docs", items: [])
        #expect(MenuResolver.isVisible(.builtin(.copyPath), in: toolbar))
        #expect(!MenuResolver.isVisible(.builtin(.deletePermanently), in: toolbar))

        let withFolder = MenuScenario(location: .toolbar, targetPath: "/Users/me/Docs", items: [folder])
        #expect(MenuResolver.isVisible(.builtin(.deletePermanently), in: withFolder))
        var copyContents = MenuItem.builtin(.copyContents)
        copyContents.isEnabled = true
        #expect(!MenuResolver.isVisible(copyContents, in: withFolder))
    }

    @Test func sidebarOffersOnlyActionsThatLeaveTheEntryInPlace() {
        let sidebar = MenuScenario(location: .sidebar, targetPath: "/Users/me",
                                   items: [SelectedItem(path: "/Users/me", isDirectory: true, isHidden: false)])
        #expect(MenuResolver.isVisible(.builtin(.copyPath), in: sidebar))
        for action in [BuiltinAction.deletePermanently, .moveTo, .copyTo, .hide, .airDrop] {
            #expect(!MenuResolver.isVisible(.builtin(action), in: sidebar), "\(action) should be hidden")
        }
    }

    @Test func unsupportedContextsAreIgnored() {
        // Copy Contents only works on files, even if the stored contexts say otherwise.
        let item = MenuItem(kind: .builtin(action: .copyContents), contexts: MenuContext.all)
        #expect(item.effectiveContexts == [.files, .toolbar])
        #expect(!MenuResolver.isVisible(item, in: items([folder])))
    }

    @Test func hideAndUnhideFollowTheHiddenState() {
        #expect(MenuResolver.isVisible(.builtin(.hide), in: items([file])))
        #expect(!MenuResolver.isVisible(.builtin(.unhide), in: items([file])))
        #expect(!MenuResolver.isVisible(.builtin(.hide), in: items([hiddenFile])))
        #expect(MenuResolver.isVisible(.builtin(.unhide), in: items([hiddenFile])))

        let unknown = SelectedItem(path: "/tmp/x", isDirectory: false, isHidden: nil)
        #expect(MenuResolver.isVisible(.builtin(.hide), in: items([unknown])))
        #expect(MenuResolver.isVisible(.builtin(.unhide), in: items([unknown])))
    }

    @Test func separatorsAreTidied() {
        let menu = MenuResolver.menu(
            for: config([.separator(), .builtin(.copyPath), .separator(), .separator(),
                         MenuItem(kind: .builtin(action: .newFile), contexts: [.background]), .separator()]),
            scenario: items([file])
        )
        #expect(titles(menu) == ["Copy Path"])
    }

    @Test func submenuLayoutWrapsEverything() {
        let menu = MenuResolver.menu(for: config([.builtin(.copyPath)], layout: .submenu), scenario: items([file]))
        #expect(menu.count == 1)
        #expect(menu.first?.title == AppIdentity.displayName)
        guard case .submenu(let children)? = menu.first?.content else {
            Issue.record("Expected a submenu")
            return
        }
        #expect(titles(children) == ["Copy Path"])
    }

    @Test func emptyMenuProducesNothing() {
        let menu = MenuResolver.menu(for: config([.separator()], layout: .submenu), scenario: items([file]))
        #expect(menu.isEmpty)
    }

    @Test func newFileListsEnabledTemplatesAndDisappearsWithoutAny() throws {
        var config = config([.builtin(.newFile)])
        let folderMenu = MenuResolver.menu(for: config, scenario: items([folder]))
        guard case .submenu(let templates)? = folderMenu.first?.content else {
            Issue.record("Expected the New File submenu")
            return
        }
        #expect(titles(templates) == FileTemplate.builtins.filter(\.isEnabled).map(\.name))
        let first = try #require(templates.first)
        #expect(first.content == .action(ActionTarget(itemID: config.items[0].id, option: "builtin.text")))

        for index in config.templates.indices { config.templates[index].isEnabled = false }
        #expect(MenuResolver.menu(for: config, scenario: items([folder])).isEmpty)
    }

    @Test func copyToOffersQuickFoldersAndChooseFolder() {
        var config = config([.builtin(.copyTo)])
        let documents = QuickFolder(path: "/Users/me/Documents")
        config.quickFolders = [documents]
        let menu = MenuResolver.menu(for: config, scenario: items([file]))
        guard case .submenu(let children)? = menu.first?.content else {
            Issue.record("Expected the Copy To submenu")
            return
        }
        #expect(titles(children) == ["Documents", "—", "Choose Folder…"])

        config.quickFolders = []
        guard case .submenu(let onlyChoose)? = MenuResolver.menu(for: config, scenario: items([file])).first?.content else {
            Issue.record("Expected the Copy To submenu")
            return
        }
        #expect(titles(onlyChoose) == ["Choose Folder…"])
    }

    @Test func pausedOrExcludedShowsNothing() {
        var paused = config([.builtin(.copyPath)])
        paused.isPaused = true
        #expect(MenuResolver.menu(for: paused, scenario: items([file])).isEmpty)

        var excluded = config([.builtin(.copyPath)])
        excluded.excludedFolders = ["/Users/me"]
        #expect(MenuResolver.menu(for: excluded, scenario: items([file])).isEmpty)
        excluded.excludedFolders = ["/Users/me/Doc"]
        #expect(!MenuResolver.menu(for: excluded, scenario: items([file])).isEmpty)
    }

    @Test func openWithNodesCarryTheAppPath() {
        let app = OpenWithApp(appPath: "/Applications/Zed.app", appName: "Zed", bundleID: "dev.zed.Zed")
        let menu = MenuResolver.menu(for: config([MenuItem(kind: .openWith(app: app))]), scenario: items([file]))
        #expect(menu.first?.title == "Open in Zed")
        #expect(menu.first?.appPath == "/Applications/Zed.app")
    }
}
