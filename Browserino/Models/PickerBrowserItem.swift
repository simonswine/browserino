//
//  PickerBrowserItem.swift
//  Browserino
//

import Foundation

struct PickerBrowser: Equatable {
    let appURL: URL
    let bundleIdentifier: String
    let displayName: String
}

struct PickerBrowserItem: Identifiable, Equatable {
    let id: String
    let orderKey: String
    let appURL: URL
    let displayName: String?
    let profileDirectory: String?
    let shortcutKey: String?
}

enum PickerBrowserItemBuilder {
    static func makeItems(
        browsers: [PickerBrowser],
        chromeProfilesEnabled: Bool,
        chromeProfiles: [ChromeProfile],
        shortcuts: [String: String],
        browserOrder: [String] = [],
        includeHiddenProfiles: Bool = false
    ) -> [PickerBrowserItem] {
        let items = browsers.flatMap { browser in
            guard chromeProfilesEnabled,
                  browser.bundleIdentifier == ChromeProfileUtil.chromeBundleID,
                  !chromeProfiles.isEmpty
            else {
                return [genericItem(for: browser, shortcuts: shortcuts)]
            }

            return chromeProfiles.compactMap { profile in
                guard includeHiddenProfiles || !profile.isHidden else {
                    return nil
                }

                let profileID = "\(browser.bundleIdentifier)::\(profile.directoryName)"
                return PickerBrowserItem(
                    id: profileID,
                    orderKey: profileID,
                    appURL: browser.appURL,
                    displayName: "\(browser.displayName) - \(profile.displayName)",
                    profileDirectory: profile.directoryName,
                    shortcutKey: shortcuts[profileID]
                )
            }
        }

        return BrowserOrder.sort(items, using: browserOrder)
    }

    private static func genericItem(
        for browser: PickerBrowser,
        shortcuts: [String: String]
    ) -> PickerBrowserItem {
        PickerBrowserItem(
            id: browser.appURL.absoluteString,
            orderKey: browser.appURL.absoluteString,
            appURL: browser.appURL,
            displayName: nil,
            profileDirectory: nil,
            shortcutKey: shortcuts[browser.bundleIdentifier]
        )
    }
}

enum BrowserOrder {
    static func sort(_ items: [PickerBrowserItem], using order: [String]) -> [PickerBrowserItem] {
        var positions: [String: Int] = [:]
        for (index, key) in order.enumerated() where positions[key] == nil {
            positions[key] = index
        }

        return items.enumerated().sorted { lhs, rhs in
            let lhsPosition = positions[lhs.element.orderKey] ?? order.count + lhs.offset
            let rhsPosition = positions[rhs.element.orderKey] ?? order.count + rhs.offset
            return lhsPosition == rhsPosition ? lhs.offset < rhs.offset : lhsPosition < rhsPosition
        }
        .map(\.element)
    }

    static func merge(
        existing: [String],
        browserKeys: [String],
        chromeBrowserKeys: [String],
        profileKeys: [String]
    ) -> [String] {
        let validKeys = Set(browserKeys + profileKeys)
        var result = existing.filter { validKeys.contains($0) }
        if result.isEmpty {
            result = browserKeys
        }
        let missingProfileKeys = profileKeys.filter { !result.contains($0) }

        if !missingProfileKeys.isEmpty {
            if let lastProfileIndex = result.lastIndex(where: { profileKeys.contains($0) }) {
                result.insert(contentsOf: missingProfileKeys, at: lastProfileIndex + 1)
            } else if let chromeIndex = result.firstIndex(where: { chromeBrowserKeys.contains($0) }) {
                result.insert(contentsOf: missingProfileKeys, at: chromeIndex)
            } else {
                result.append(contentsOf: missingProfileKeys)
            }
        }

        result.append(contentsOf: browserKeys.filter { !result.contains($0) })
        return result
    }

    static func move(
        _ existing: [String],
        visibleKeys: [String],
        from source: IndexSet,
        to destination: Int
    ) -> [String] {
        var visibleOrder = existing.filter { visibleKeys.contains($0) }
        visibleOrder.append(contentsOf: visibleKeys.filter { !visibleOrder.contains($0) })

        let moved = source.map { visibleOrder[$0] }
        for index in source.sorted(by: >) {
            visibleOrder.remove(at: index)
        }

        let insertionIndex = destination - source.filter { $0 < destination }.count
        visibleOrder.insert(contentsOf: moved, at: insertionIndex)

        var iterator = visibleOrder.makeIterator()
        return existing.map { key in
            visibleKeys.contains(key) ? iterator.next()! : key
        } + Array(iterator)
    }
}
