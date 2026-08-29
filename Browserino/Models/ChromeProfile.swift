//
//  ChromeProfile.swift
//  Browserino
//

import AppKit
import Foundation

struct ChromeProfile: Codable, Hashable {
    var directoryName: String
    var displayName: String
    var isHidden: Bool = false
}

class ChromeProfileUtil {
    static let chromeBundleID = "com.google.Chrome"

    private struct LocalState: Decodable {
        let profile: Profile
    }

    private struct Profile: Decodable {
        let infoCache: [String: ProfileInfo]

        enum CodingKeys: String, CodingKey {
            case infoCache = "info_cache"
        }
    }

    private struct ProfileInfo: Decodable {
        let name: String
    }

    static func chromeURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleID)
    }

    static func detectProfiles() throws -> [ChromeProfile] {
        let localStatePath = NSString("~/Library/Application Support/Google/Chrome/Local State")
            .expandingTildeInPath

        return try parseProfiles(from: Data(contentsOf: URL(fileURLWithPath: localStatePath)))
    }

    static func parseProfiles(from data: Data) throws -> [ChromeProfile] {
        let localState = try JSONDecoder().decode(LocalState.self, from: data)

        return localState.profile.infoCache.map { directoryName, info in
            return ChromeProfile(
                directoryName: directoryName,
                displayName: info.name
            )
        }
        .sorted { $0.directoryName < $1.directoryName }
    }

    static func mergeProfiles(
        detected: [ChromeProfile],
        preserving saved: [ChromeProfile]
    ) -> [ChromeProfile] {
        detected.map { profile in
            guard let existing = saved.first(where: { $0.directoryName == profile.directoryName }) else {
                return profile
            }

            return ChromeProfile(
                directoryName: existing.directoryName,
                displayName: existing.displayName,
                isHidden: existing.isHidden
            )
        }
    }

    static func refreshProfiles(
        current: [ChromeProfile],
        detect: () throws -> [ChromeProfile]
    ) throws -> [ChromeProfile] {
        mergeProfiles(detected: try detect(), preserving: current)
    }

    static func migrateLegacyShortcut(
        _ shortcuts: inout [String: String],
        to profiles: [ChromeProfile]
    ) {
        guard let legacyShortcut = shortcuts[chromeBundleID],
              let destination = profiles.first(where: { $0.directoryName == "Default" }) ?? profiles.first
        else {
            return
        }

        let profileID = "\(chromeBundleID)::\(destination.directoryName)"
        if shortcuts[profileID] == nil {
            shortcuts[profileID] = legacyShortcut
        }
        shortcuts[chromeBundleID] = nil
    }
}
