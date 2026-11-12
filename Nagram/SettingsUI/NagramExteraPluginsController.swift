import AccountContext
import Display
import Foundation
import ItemListUI
import LegacyMediaPickerUI
import NagramPlugins
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private struct NagramExteraEntry: ItemListNodeEntry {
    enum Kind: Equatable {
        case action, destructive, disclosure(String), toggle(Bool), header, footer
    }

    let stableId: Int
    let section: ItemListSectionId
    let title: String
    let kind: Kind

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let action = arguments as! (Int) -> Void
        switch self.kind {
        case .action, .destructive:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title, kind: self.kind == .destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { action(self.stableId) })
        case let .disclosure(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: self.title, label: label, sectionId: self.section, style: .blocks, action: { action(self.stableId) })
        case let .toggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title, value: value, enableInteractiveChanges: false, sectionId: self.section, style: .blocks, updated: { _ in action(self.stableId) })
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        }
    }
}

func nagramExteraPluginsController(context: AccountContext, plugin: NagramExteraPlugin? = nil, updated: (() -> Void)? = nil) -> ViewController {
    let engine = NagramExteraPlugins.shared
    let update = ValuePromise<Int>(0, ignoreRepeated: false)
    var generation = 0
    var rows: [NagramExteraSetting] = []
    weak var controller: ItemListController?

    func refresh() {
        generation += 1
        update.set(generation)
    }

    func presentError(_ error: Error) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: ngI18n("Nagram.ExteraPlugins", data.strings.baseLanguageCode), text: error.localizedDescription, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})
        ]), in: .window(.root))
    }

    func loadRows(_ plugin: NagramExteraPlugin) {
        guard engine.enabled.contains(plugin.id) else {
            rows = []
            refresh()
            return
        }
        engine.settings(plugin.id) { result in
            switch result {
            case let .success(value):
                rows = value
            case let .failure(error):
                rows = []
                presentError(error)
            }
            refresh()
        }
    }

    func importPlugin() {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        let picker = legacyICloudFilePicker(theme: data.theme, mode: .import, documentTypes: ["public.data"], completion: { urls in
            guard let url = urls.first else { return }
            do {
                guard url.pathExtension.lowercased() == "plugin" else {
                    throw NSError(domain: "Nextgram.Extera", code: 1, userInfo: [NSLocalizedDescriptionKey: ngI18n("Nagram.ExteraPlugins.FileType", lang)])
                }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard let bytes = try handle.read(upToCount: 2 * 1024 * 1024 + 1),
                      bytes.count <= 2 * 1024 * 1024,
                      let source = String(data: bytes, encoding: .utf8) else {
                    throw NSError(domain: "Nextgram.Extera", code: 2, userInfo: [NSLocalizedDescriptionKey: ngI18n("Nagram.ExteraPlugins.FileType", lang)])
                }
                engine.inspect(source: source) { result in
                    do {
                        let metadata = try result.get()
                        let details = [metadata.id, metadata.author, metadata.version, metadata.description].filter { !$0.isEmpty }.joined(separator: "\n")
                        controller?.present(textAlertController(context: context, title: metadata.name, text: details, actions: [
                            TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                            TextAlertAction(type: .defaultAction, title: ngI18n("Nagram.ExteraPlugins.Import", lang), action: {
                                do {
                                    try engine.install(source: source, plugin: metadata)
                                    refresh()
                                } catch {
                                    presentError(error)
                                }
                            })
                        ]), in: .window(.root))
                    } catch {
                        presentError(error)
                    }
                }
            } catch {
                presentError(error)
            }
        })
        controller?.present(picker, in: .window(.root))
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, update.get())
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = data.strings.baseLanguageCode
        let title = plugin?.name ?? ngI18n("Nagram.ExteraPlugins", lang)
        var entries: [NagramExteraEntry] = []
        var actions: [Int: () -> Void] = [:]
        func add(_ title: String, _ kind: NagramExteraEntry.Kind, section: ItemListSectionId, action: (() -> Void)? = nil) {
            let id = entries.count
            entries.append(NagramExteraEntry(stableId: id, section: section, title: title, kind: kind))
            actions[id] = action
        }

        if let plugin {
            let enabled = engine.enabled.contains(plugin.id)
            add(ngI18n("Nagram.ExteraPlugins.Enable", lang), .toggle(enabled), section: 0) {
                let change: () -> Void = {
                    engine.setEnabled(plugin, enabled: !enabled) { result in
                        if case let .failure(error) = result {
                            presentError(error)
                        }
                        loadRows(plugin)
                    }
                }
                if enabled {
                    change()
                } else {
                    controller?.present(textAlertController(context: context, title: plugin.name, text: ngI18n("Nagram.ExteraPlugins.Trust", lang), actions: [
                        TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: ngI18n("Nagram.ExteraPlugins.Enable", lang), action: change)
                    ]), in: .window(.root))
                }
            }
            var section: ItemListSectionId = 1
            if enabled {
                for row in rows {
                    if row.kind == "Header" {
                        section += 1
                        add(row.text, .header, section: section)
                    } else if let key = row.key, let value = row.boolValue {
                        add(row.text, .toggle(value), section: section) {
                            engine.setSetting(plugin.id, key: key, value: !value) { result in
                                if case let .failure(error) = result { presentError(error) }
                                loadRows(plugin)
                            }
                        }
                    } else if let key = row.key, let value = row.stringValue {
                        add(row.text, .disclosure(value), section: section) {
                            let alert = UIAlertController(title: row.text, message: row.subtext, preferredStyle: .alert)
                            alert.addTextField { $0.text = value }
                            alert.addAction(UIAlertAction(title: data.strings.Common_Cancel, style: .cancel))
                            alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default, handler: { [weak alert] _ in
                                guard let text = alert?.textFields?.first?.text else { return }
                                engine.setSetting(plugin.id, key: key, value: text) { result in
                                    if case let .failure(error) = result { presentError(error) }
                                    loadRows(plugin)
                                }
                            }))
                            controller?.present(alert, animated: true)
                        }
                    } else {
                        add(row.text, .footer, section: section)
                    }
                    if let subtext = row.subtext, !subtext.isEmpty {
                        add(subtext, .footer, section: section)
                    }
                }
            } else {
                add(ngI18n("Nagram.ExteraPlugins.Remove", lang), .destructive, section: section) {
                    let remove = ngI18n("Nagram.ExteraPlugins.Remove", lang)
                    controller?.present(textAlertController(context: context, title: remove, text: plugin.name, actions: [
                        TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: remove, action: {
                            do {
                                try engine.remove(plugin)
                                updated?()
                                let _ = controller?.navigationController?.popViewController(animated: true)
                            } catch {
                                presentError(error)
                            }
                        })
                    ]), in: .window(.root))
                }
            }
        } else {
            add(ngI18n("Nagram.ExteraPlugins.Import", lang), .action, section: 0, action: importPlugin)
            add(ngI18n("Nagram.ExteraPlugins.Footer", lang), .footer, section: 0)
            for item in engine.plugins {
                add(item.name, .disclosure(item.version), section: 1) {
                    controller?.navigationController?.pushViewController(nagramExteraPluginsController(context: context, plugin: item, updated: refresh), animated: true)
                }
            }
        }
        let presentation = ItemListPresentationData(data)
        let state = ItemListControllerState(presentationData: presentation, title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let list = ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false)
        let action: (Int) -> Void = { index in actions[index]?() }
        return (state, (list, action))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    if let plugin, engine.enabled.contains(plugin.id) {
        var didLoad = false
        result.afterLayout {
            if !didLoad {
                didLoad = true
                loadRows(plugin)
            }
        }
    }
    result.navigationPresentation = .default
    return result
}
