import AccountContext
import Display
import Foundation
import ItemListUI
import LegacyMediaPickerUI
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import UIKit

private enum NextgramSettingsBackupAction: Equatable {
    case export
    case open
    case restore
    case cancelPreview
}

private struct NextgramSettingsBackupEntry: ItemListNodeEntry {
    enum Content: Equatable {
        case category(NextgramSettingsCategory, selected: Bool, count: Int?, enabled: Bool)
        case action(NextgramSettingsBackupAction)
        case footer
    }

    struct Arguments {
        let toggle: (NextgramSettingsCategory, Bool) -> Void
        let perform: (NextgramSettingsBackupAction) -> Void
    }

    let stableId: Int
    let section: Int32
    let title: String
    let content: Content

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! Arguments
        switch self.content {
        case let .category(category, selected, count, enabled):
            let title = count.map { "\(self.title) (\($0))" } ?? self.title
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass,
                title: title, value: selected, enabled: enabled, sectionId: self.section, style: .blocks,
                updated: { arguments.toggle(category, $0) })
        case let .action(action):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title,
                kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks,
                action: { arguments.perform(action) })
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        }
    }
}

func nextgramSettingsBackupController(context: AccountContext) -> ViewController {
    let allCategories = Set(NextgramSettingsCategory.allCases)
    var selected = allCategories
    var exportSelection = allCategories
    var backup: NextgramSettingsBackup?
    var restoring = false
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let refresh = {
        revision += 1
        updates.set(revision)
    }
    var present: ((ViewController) -> Void)?
    let alert: (String) -> Void = { messageKey in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        present?(textAlertController(context: context, title: ngI18n("Nagram.Settings.Backup", lang),
            text: ngI18n(messageKey, lang), actions: [
                TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})
            ]))
    }
    let arguments = NextgramSettingsBackupEntry.Arguments(toggle: { category, value in
        if value {
            selected.insert(category)
        } else {
            selected.remove(category)
        }
        refresh()
    }, perform: { action in
        guard !restoring else { return }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        switch action {
        case .export:
            guard !selected.isEmpty else { return }
            let categories = selected
            let finish: (NagramBottomBarSettings) -> Void = { bottomBar in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let url = folder.appendingPathComponent("Nextgram-Settings.json")
                do {
                    let archive = try NextgramSettingsBackup.export(categories: categories, bottomBar: bottomBar,
                        appIconName: context.sharedContext.applicationBindings.getAlternateIconName())
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try archive.write(to: url, options: .atomic)
                    present?(legacyICloudFilePicker(theme: data.theme, mode: .export, url: url,
                        completion: { _ in try? FileManager.default.removeItem(at: folder) }))
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    alert("Nagram.Settings.Backup.ExportFailed")
                }
            }
            var bottomBar = NagramSettings.shared.bottomBarSettings
            if categories.contains(.appearance) {
                let _ = (context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
                |> take(1)
                |> deliverOnMainQueue).startStandalone(next: { sharedData in
                    let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings
                    bottomBar.setVisible(.calls, visible: settings.showTab)
                    finish(bottomBar)
                })
            } else {
                finish(bottomBar)
            }
        case .open:
            present?(legacyICloudFilePicker(theme: data.theme, mode: .import, documentTypes: ["public.json"], completion: { urls in
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let bytes = try file.read(upToCount: NextgramSettingsBackup.maximumFileSize + 1) ?? Data()
                    let candidate = try NextgramSettingsBackup(data: bytes)
                    exportSelection = selected
                    backup = candidate
                    selected = Set(candidate.counts.keys)
                    refresh()
                } catch {
                    alert("Nagram.Settings.Backup.Invalid")
                }
            }))
        case .restore:
            guard let candidate = backup, !selected.isEmpty else { return }
            let categories = selected
            present?(textAlertController(context: context, title: ngI18n("Nagram.Settings.Backup.Restore", lang),
                text: ngI18n("Nagram.Settings.Backup.Confirm", lang), actions: [
                    TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: ngI18n("Nagram.Settings.Backup.Restore", lang), action: {
                        restoring = true
                        refresh()
                        let finish: (Bool) -> Void = { notificationAllowed in
                            let complete: (Bool) -> Void = { iconRestored in
                                restoring = false
                                backup = nil
                                selected = exportSelection
                                refresh()
                                alert(notificationAllowed && iconRestored ? "Nagram.Settings.Backup.Restored" : "Nagram.Settings.Backup.Partial")
                            }
                            let restoreIcon = {
                                let bindings = context.sharedContext.applicationBindings
                                guard let icon = candidate.appIcon(in: categories), icon.name != bindings.getAlternateIconName() else {
                                    complete(true)
                                    return
                                }
                                guard bindings.getAvailableAlternateIcons().contains(where: { $0.isDefault ? icon.name == nil : $0.name == icon.name }) else {
                                    complete(false)
                                    return
                                }
                                bindings.requestSetAlternateIconName(icon.name) { success in
                                    Queue.mainQueue().async { complete(success) }
                                }
                            }
                            if let enabled = candidate.notificationFallback(in: categories) {
                                NagramSettings.shared.localNotificationFallbackEnabled = enabled && notificationAllowed
                            }
                            if let bottomBar = candidate.restore(categories: categories) {
                                let _ = (updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
                                    $0.withUpdatedShowTab(bottomBar.isVisible(.calls))
                                })
                                |> deliverOnMainQueue).startStandalone(completed: restoreIcon)
                            } else {
                                restoreIcon()
                            }
                        }
                        if candidate.notificationFallback(in: categories) == true && !NagramSettings.shared.localNotificationFallbackEnabled {
                            context.sharedContext.applicationBindings.registerForNotifications { allowed in
                                Queue.mainQueue().async { finish(allowed) }
                            }
                        } else {
                            finish(true)
                        }
                    })
                ]))
        case .cancelPreview:
            backup = nil
            selected = exportSelection
            refresh()
        }
    })
    let state = combineLatest(context.sharedContext.presentationData, updates.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let data = ItemListPresentationData(presentationData)
        let strings = presentationData.strings
        let lang = strings.baseLanguageCode
        let counts = backup?.counts
        var entries: [NextgramSettingsBackupEntry] = []
        func append(_ titleKey: String, _ content: NextgramSettingsBackupEntry.Content, section: Int32) {
            entries.append(NextgramSettingsBackupEntry(stableId: entries.count, section: section,
                title: ngI18n(titleKey, lang), content: content))
        }
        for category in NextgramSettingsCategory.allCases {
            let count = counts?[category]
            append(category.titleKey, .category(category, selected: selected.contains(category), count: count,
                enabled: !restoring && (counts == nil || count != nil)), section: 0)
        }
        if counts != nil {
            append("Nagram.Settings.Backup.Preview", .footer, section: 0)
            if !restoring {
                if !selected.isEmpty {
                    append("Nagram.Settings.Backup.Restore", .action(.restore), section: 1)
                }
                append("Nagram.Settings.Backup.CancelPreview", .action(.cancelPreview), section: 1)
            }
        } else {
            append("Nagram.Settings.Backup.Scope", .footer, section: 0)
            if !selected.isEmpty {
                append("Nagram.Settings.Backup.Export", .action(.export), section: 1)
            }
            append("Nagram.Settings.Backup.Open", .action(.open), section: 1)
        }
        return (
            ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.Settings.Backup", lang)),
                leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back)),
            (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), arguments)
        )
    }
    let controller = ItemListController(context: context, state: state)
    present = { [weak controller] value in
        controller?.present(value, in: .window(.root))
    }
    return controller
}
