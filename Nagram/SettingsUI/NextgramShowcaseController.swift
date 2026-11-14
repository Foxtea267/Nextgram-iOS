import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import PhoneNumberFormat
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import UIKit

// The section order and explicit save actions follow Regram's LocalGiftsController.
private enum ShowcaseField: Int32, Hashable {
    case countryCode, phone, rating, stars, ton
}

private struct ShowcaseFieldTag: ItemListItemTag {
    let field: ShowcaseField

    func isEqual(to other: ItemListItemTag) -> Bool {
        return (other as? ShowcaseFieldTag)?.field == self.field
    }
}

private enum ShowcaseSwitch: Equatable {
    case premium, phone, rating, balances, ton
}

private struct ShowcaseEntry: ItemListNodeEntry {
    enum Content: Equatable {
        case heading(String)
        case note(String)
        case input(ShowcaseField, String, String, String)
        case toggle(ShowcaseSwitch, String, Bool)
        case save(ShowcaseField, String)
        case balance(ShowcaseField, String, String)
    }

    let stableId: Int32
    let section: ItemListSectionId
    let content: Content

    var tag: ItemListItemTag? {
        if case let .input(field, _, _, _) = self.content {
            return ShowcaseFieldTag(field: field)
        }
        return nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! ShowcaseActions
        switch self.content {
        case let .heading(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .note(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .input(field, title, value, placeholder):
            let type: ItemListSingleLineInputItemType
            switch field {
            case .countryCode, .phone, .stars: type = .number
            case .ton: type = .decimal
            case .rating: type = .regular(capitalization: false, autocorrection: false)
            }
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: value, placeholder: placeholder, type: type, returnKeyType: .done, alignment: .right, spacing: 8.0, clearType: .onFocus,
                tag: self.tag, sectionId: self.section, textUpdated: { actions.edit(field, $0) }, action: {
                    actions.save(field == .countryCode ? .phone : field)
                })
        case let .toggle(key, title, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: enabled, enableInteractiveChanges: key != .phone && key != .rating, sectionId: self.section, style: .blocks, updated: { actions.toggle(key, $0) })
        case let .save(field, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { actions.save(field) })
        case let .balance(field, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass,
                icon: field == .ton ? PresentationResourcesSettings.ton : PresentationResourcesSettings.stars,
                title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        }
    }
}

private struct ShowcaseActions {
    let edit: (ShowcaseField, String) -> Void
    let toggle: (ShowcaseSwitch, Bool) -> Void
    let save: (ShowcaseField) -> Void
}

func nextgramShowcaseController(context: AccountContext, focus: String? = nil) -> ViewController {
    let settings = NagramSettings.shared
    let digits: (String) -> String = { $0.filter { "0123456789".contains($0) } }
    let phone = digits(settings.localProfilePhone)
    let countryCode = phone.hasPrefix("888") ? "888" : (lookupCountryIdByNumber(phone, configuration: context.currentCountriesConfiguration.with { $0 })?.1.code ?? "")
    let initial: [ShowcaseField: String] = [
        .countryCode: countryCode, .phone: String(phone.dropFirst(countryCode.count)),
        .rating: settings.localProfileRating, .stars: settings.localProfileStars, .ton: settings.localProfileTon
    ]
    let drafts = ValuePromise(initial, ignoreRepeated: true)
    var values = initial
    let refresh = ValuePromise<Int>(0, ignoreRepeated: true)
    var revision = 0
    var presentError: ((String) -> Void)?
    var dismissInput: (() -> Void)?
    let bump = {
        revision += 1
        refresh.set(revision)
    }
    let save: (ShowcaseField) -> Bool = { field in
        let value = (values[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .phone, .countryCode:
            let code = digits(values[.countryCode] ?? "")
            let number = digits(values[.phone] ?? "")
            let full = code + number
            guard (1...3).contains(code.count), !code.hasPrefix("0"), !number.isEmpty,
                  (7...15).contains(full.count), code != "888" || number.count == 8 else {
                presentError?("PhoneInvalid")
                return false
            }
            settings.localProfilePhone = "+" + full
            settings.nextgramShowcasePhoneEnabled = true
        case .rating:
            guard let level = Int32(value), (-100_000...100_000).contains(level) else {
                presentError?("RatingInvalid")
                return false
            }
            settings.localProfileRating = String(level)
            settings.nextgramShowcaseRatingEnabled = true
        case .stars:
            guard let amount = UInt64(value), amount <= 999_999_999_999 else {
                presentError?("AmountInvalid")
                return false
            }
            settings.localProfileStars = String(amount)
        case .ton:
            let normalized = value.replacingOccurrences(of: ",", with: ".")
            let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, !normalized.isEmpty,
                  normalized.allSatisfy({ "0123456789.".contains($0) }),
                  (parts.last?.count ?? 0) <= (parts.count == 2 ? 9 : 10),
                  let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), amount >= 0, amount <= 1_000_000_000 else {
                presentError?("AmountInvalid")
                return false
            }
            settings.localProfileTon = NSDecimalNumber(decimal: amount).stringValue
        }
        return true
    }
    let actions = ShowcaseActions(edit: { field, value in
        values[field] = value
        drafts.set(values)
    }, toggle: { key, enabled in
        switch key {
        case .premium: settings.localPremiumEnabled = enabled
        case .phone:
            if enabled {
                _ = save(.phone)
            } else {
                settings.nextgramShowcasePhoneEnabled = false
            }
        case .rating:
            if enabled {
                _ = save(.rating)
            } else {
                settings.nextgramShowcaseRatingEnabled = false
            }
        case .balances:
            // Freeze the inherited visibility before changing the old shared switch.
            let showsPhone = settings.nextgramShowcasePhoneEnabled
            let showsRating = settings.nextgramShowcaseRatingEnabled
            settings.nextgramShowcasePhoneEnabled = showsPhone
            settings.nextgramShowcaseRatingEnabled = showsRating
            settings.showLocalProfileCard = enabled
        case .ton: settings.nextgramShowcaseTonEnabled = enabled
        }
        bump()
    }, save: { field in
        if save(field) {
            dismissInput?()
            bump()
        }
    })

    let focusField: ShowcaseField?
    switch focus {
    case "Nagram.Showcase.Phone": focusField = .phone
    case "Nagram.Showcase.Rating": focusField = .rating
    case "Nagram.Showcase.Stars": focusField = .stars
    case "Nagram.Showcase.Ton": focusField = .ton
    default: focusField = nil
    }
    let state = combineLatest(context.sharedContext.presentationData, drafts.get(), refresh.get())
    |> deliverOnMainQueue
    |> map { data, draft, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = data.strings.baseLanguageCode
        func s(_ key: String) -> String { ngI18n("Nagram.Showcase." + key, lang) }
        var entries: [ShowcaseEntry] = []
        func add(_ id: Int32, _ section: Int32, _ content: ShowcaseEntry.Content) {
            entries.append(ShowcaseEntry(stableId: id, section: section, content: content))
        }
        add(0, 0, .toggle(.premium, ngI18n("Nagram.LocalPremium", lang), settings.localPremiumEnabled))
        add(1, 0, .note(ngI18n("Nagram.LocalPremium.Footer", lang)))
        add(10, 1, .heading(s("Phone")))
        add(11, 1, .input(.countryCode, s("CountryCode"), draft[.countryCode] ?? "", "+888"))
        add(12, 1, .input(.phone, s("PhoneNumber"), draft[.phone] ?? "", s("Optional")))
        add(13, 1, .toggle(.phone, s("ShowPhone"), settings.nextgramShowcasePhoneEnabled && !settings.localProfilePhone.isEmpty))
        add(14, 1, .save(.phone, s("SavePhone")))
        add(15, 1, .note(s("PhoneHint")))
        add(20, 2, .heading(s("Rating")))
        add(21, 2, .input(.rating, s("RatingLevel"), draft[.rating] ?? "", "0"))
        add(22, 2, .toggle(.rating, s("ShowRating"), settings.nextgramShowcaseRatingEnabled && !settings.localProfileRating.isEmpty))
        add(23, 2, .save(.rating, s("SaveRating")))
        add(24, 2, .note(s("RatingHint")))
        add(30, 3, .toggle(.balances, s("ProfileCard"), settings.showLocalProfileCard))
        add(31, 3, .note(s("Footer")))
        if settings.showLocalProfileCard {
            add(40, 4, .heading(s("Stars")))
            add(41, 4, .input(.stars, s("Stars"), draft[.stars] ?? "", "0"))
            add(42, 4, .save(.stars, s("SaveStars")))
            add(43, 4, .balance(.stars, s("CurrentBalance"), settings.localProfileStars.isEmpty ? "0" : settings.localProfileStars))
            add(50, 5, .heading(s("Ton")))
            add(51, 5, .input(.ton, s("Ton"), draft[.ton] ?? "", "0"))
            add(52, 5, .save(.ton, s("SaveTon")))
            add(53, 5, .toggle(.ton, s("ShowTon"), settings.nextgramShowcaseTonEnabled))
            add(54, 5, .balance(.ton, s("CurrentBalance"), settings.localProfileTon.isEmpty ? "0" : settings.localProfileTon))
        }
        let presentation = ItemListPresentationData(data)
        let focusIndex = focusField.flatMap { field in
            entries.firstIndex(where: { ($0.tag as? ShowcaseFieldTag)?.field == field })
                ?? entries.firstIndex(where: { $0.stableId == 30 })
        }
        let scrollToItem = focusIndex.map { ListViewScrollToItem(index: $0, position: .visible, animated: false, curve: .Default(duration: nil), directionHint: .Down) }
        return (
            ItemListControllerState(presentationData: presentation, title: .text(ngI18n("Nagram.Showcase", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back)),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, initialScrollToItem: scrollToItem, animateChanges: false), actions)
        )
    }
    let controller = ItemListController(context: context, state: state)
    controller.navigationPresentation = .default
    dismissInput = { [weak controller] in controller?.view.endEditing(true) }
    presentError = { [weak controller] key in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        controller?.present(textAlertController(context: context, title: ngI18n("Nagram.Showcase", lang),
            text: ngI18n("Nagram.Showcase." + key, lang),
            actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
    }
    return controller
}
