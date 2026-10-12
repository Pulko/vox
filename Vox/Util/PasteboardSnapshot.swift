import AppKit
import Foundation

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map { item in
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            return payload
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let objects: [NSPasteboardItem] = items.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            return item
        }
        if !objects.isEmpty {
            pasteboard.writeObjects(objects)
        }
    }
}
