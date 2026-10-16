import Display
import ItemListUI
import SwiftSignalKit

// MARK: NAGRAM — 子页面的「定位到某行」：设置搜索跳进子页面时滚到该行并高亮。
final class NagramSettingsFocusTag: ItemListItemTag {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? NagramSettingsFocusTag {
            return self.key == other.key
        }
        return false
    }
}

func nagramFocusScrollToItem<T: ItemListNodeEntry>(entries: [T], focusOnRow: String?) -> ListViewScrollToItem? {
    guard let focusOnRow else {
        return nil
    }
    let tag = NagramSettingsFocusTag(focusOnRow)
    guard let index = entries.firstIndex(where: { $0.tag?.isEqual(to: tag) ?? false }) else {
        return nil
    }
    return ListViewScrollToItem(index: index, position: .visible, animated: false, curve: .Default(duration: nil), directionHint: .Down)
}

func nagramHighlightFocusedRow(controller: ItemListController, focusOnRow: String?) {
    guard let focusOnRow else {
        return
    }
    let tag = NagramSettingsFocusTag(focusOnRow)
    controller.afterLayout { [weak controller] in
        var didHighlight = false
        for delay in [0.35, 0.75, 1.15] {
            Queue.mainQueue().after(delay, { [weak controller] in
                guard !didHighlight, let itemNode = controller?.itemNode(forTag: tag) as? ItemListItemNode else {
                    return
                }
                didHighlight = true
                itemNode.displayHighlight()
            })
        }
    }
}
