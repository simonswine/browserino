import Foundation
import XCTest
@testable import Browserino

final class ChromeProfileTests: XCTestCase {
    func testParseProfilesSortsDetectedProfiles() throws {
        let profiles = try ChromeProfileUtil.parseProfiles(from: Data("""
        {"profile":{"info_cache":{"Profile 1":{"name":"Work"},"Default":{"name":"Personal"}}}}
        """.utf8))

        XCTAssertEqual(
            profiles,
            [
                ChromeProfile(directoryName: "Default", displayName: "Personal"),
                ChromeProfile(directoryName: "Profile 1", displayName: "Work"),
            ]
        )
    }

    func testParseProfilesThrowsForMalformedData() {
        XCTAssertThrowsError(try ChromeProfileUtil.parseProfiles(from: Data("not json".utf8)))
    }

    func testParseProfilesThrowsWhenInfoCacheIsMissing() {
        XCTAssertThrowsError(try ChromeProfileUtil.parseProfiles(from: Data("{}".utf8)))
    }

    func testParseProfilesAllowsAnEmptyInfoCache() throws {
        XCTAssertEqual(
            try ChromeProfileUtil.parseProfiles(from: Data("{\"profile\":{\"info_cache\":{}}}".utf8)),
            []
        )
    }

    func testFailedDetectionDoesNotChangeSavedProfiles() {
        let saved = [ChromeProfile(directoryName: "Default", displayName: "Personal", isHidden: true)]

        XCTAssertThrowsError(
            try ChromeProfileUtil.refreshProfiles(current: saved) {
                try ChromeProfileUtil.parseProfiles(from: Data("not json".utf8))
            }
        )

        XCTAssertEqual(saved, [ChromeProfile(directoryName: "Default", displayName: "Personal", isHidden: true)])
    }

    func testMergeProfilesPreservesSavedCustomization() {
        let saved = [ChromeProfile(directoryName: "Default", displayName: "Personal", isHidden: true)]
        let detected = [
            ChromeProfile(directoryName: "Default", displayName: "Person 1"),
            ChromeProfile(directoryName: "Profile 1", displayName: "Work"),
        ]

        XCTAssertEqual(
            ChromeProfileUtil.mergeProfiles(detected: detected, preserving: saved),
            [
                ChromeProfile(directoryName: "Default", displayName: "Personal", isHidden: true),
                ChromeProfile(directoryName: "Profile 1", displayName: "Work"),
            ]
        )
    }

    func testMigratesLegacyShortcutToDefaultProfile() {
        var shortcuts = [ChromeProfileUtil.chromeBundleID: "c"]

        ChromeProfileUtil.migrateLegacyShortcut(
            &shortcuts,
            to: [
                ChromeProfile(directoryName: "Profile 1", displayName: "Work"),
                ChromeProfile(directoryName: "Default", displayName: "Personal"),
            ]
        )

        XCTAssertNil(shortcuts[ChromeProfileUtil.chromeBundleID])
        XCTAssertEqual(shortcuts["com.google.Chrome::Default"], "c")
    }

    func testMigratesLegacyShortcutToFirstProfileWithoutDefault() {
        var shortcuts = [ChromeProfileUtil.chromeBundleID: "c"]

        ChromeProfileUtil.migrateLegacyShortcut(
            &shortcuts,
            to: [ChromeProfile(directoryName: "Profile 1", displayName: "Work")]
        )

        XCTAssertNil(shortcuts[ChromeProfileUtil.chromeBundleID])
        XCTAssertEqual(shortcuts["com.google.Chrome::Profile 1"], "c")
    }

    func testAllHiddenProfilesProduceNoChromeItems() {
        let chrome = PickerBrowser(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            bundleIdentifier: ChromeProfileUtil.chromeBundleID,
            displayName: "Google Chrome"
        )

        let items = PickerBrowserItemBuilder.makeItems(
            browsers: [chrome],
            chromeProfilesEnabled: true,
            chromeProfiles: [ChromeProfile(directoryName: "Default", displayName: "Personal", isHidden: true)],
            shortcuts: [ChromeProfileUtil.chromeBundleID: "c"]
        )

        XCTAssertTrue(items.isEmpty)
    }

    func testDisabledProfileExpansionKeepsGenericChromeItem() {
        let chrome = PickerBrowser(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            bundleIdentifier: ChromeProfileUtil.chromeBundleID,
            displayName: "Google Chrome"
        )

        let items = PickerBrowserItemBuilder.makeItems(
            browsers: [chrome],
            chromeProfilesEnabled: false,
            chromeProfiles: [ChromeProfile(directoryName: "Default", displayName: "Personal")],
            shortcuts: [ChromeProfileUtil.chromeBundleID: "c"]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, chrome.appURL.absoluteString)
        XCTAssertNil(items[0].profileDirectory)
        XCTAssertEqual(items[0].shortcutKey, "c")
    }

    func testProfilesCanBeOrderedBetweenOtherBrowsers() {
        let safari = PickerBrowser(
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        )
        let chrome = PickerBrowser(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            bundleIdentifier: ChromeProfileUtil.chromeBundleID,
            displayName: "Google Chrome"
        )
        let firefox = PickerBrowser(
            appURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox"
        )

        let profileID = "com.google.Chrome::Profile 1"
        let items = PickerBrowserItemBuilder.makeItems(
            browsers: [safari, chrome, firefox],
            chromeProfilesEnabled: true,
            chromeProfiles: [ChromeProfile(directoryName: "Profile 1", displayName: "Work")],
            shortcuts: [:],
            browserOrder: [safari.appURL.absoluteString, profileID, firefox.appURL.absoluteString]
        )

        XCTAssertEqual(items.map(\.orderKey), [safari.appURL.absoluteString, profileID, firefox.appURL.absoluteString])
        XCTAssertEqual(items[1].displayName, "Google Chrome - Work")
        XCTAssertEqual(items[1].profileDirectory, "Profile 1")
    }

    func testInitialProfileOrderUsesChromePosition() {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app").absoluteString
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app").absoluteString
        let firefox = URL(fileURLWithPath: "/Applications/Firefox.app").absoluteString
        let profileID = "com.google.Chrome::Default"

        XCTAssertEqual(
            BrowserOrder.merge(
                existing: [],
                browserKeys: [safari, chrome, firefox],
                chromeBrowserKeys: [chrome],
                profileKeys: [profileID]
            ),
            [safari, profileID, chrome, firefox]
        )
    }

    func testNewProfilesFollowExistingChromeProfiles() {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app").absoluteString
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app").absoluteString
        let firefox = URL(fileURLWithPath: "/Applications/Firefox.app").absoluteString
        let defaultProfile = "com.google.Chrome::Default"
        let workProfile = "com.google.Chrome::Profile 1"

        XCTAssertEqual(
            BrowserOrder.merge(
                existing: [safari, defaultProfile, firefox, chrome],
                browserKeys: [safari, chrome, firefox],
                chromeBrowserKeys: [chrome],
                profileKeys: [defaultProfile, workProfile]
            ),
            [safari, defaultProfile, workProfile, firefox, chrome]
        )
    }
}
