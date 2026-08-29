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
        shortcuts: [String: String]
    ) -> [PickerBrowserItem] {
        browsers.flatMap { browser in
            guard chromeProfilesEnabled,
                  browser.bundleIdentifier == ChromeProfileUtil.chromeBundleID,
                  !chromeProfiles.isEmpty
            else {
                return [genericItem(for: browser, shortcuts: shortcuts)]
            }

            return chromeProfiles.compactMap { profile in
                guard !profile.isHidden else {
                    return nil
                }

                let profileID = "\(browser.bundleIdentifier)::\(profile.directoryName)"
                return PickerBrowserItem(
                    id: profileID,
                    appURL: browser.appURL,
                    displayName: "\(browser.displayName) - \(profile.displayName)",
                    profileDirectory: profile.directoryName,
                    shortcutKey: shortcuts[profileID]
                )
            }
        }
    }

    private static func genericItem(
        for browser: PickerBrowser,
        shortcuts: [String: String]
    ) -> PickerBrowserItem {
        PickerBrowserItem(
            id: browser.bundleIdentifier,
            appURL: browser.appURL,
            displayName: nil,
            profileDirectory: nil,
            shortcutKey: shortcuts[browser.bundleIdentifier]
        )
    }
}
