//
//  BrowsersTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct BrowsersTab: View {
    @AppStorage("browsers") private var browsers: [URL] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [URL] = []
    @AppStorage("privateArgs") private var privateArgs: [String: String] = [:]
    @AppStorage("chromeProfiles") private var chromeProfiles: [ChromeProfile] = []
    @AppStorage("chromeProfilesEnabled") private var chromeProfilesEnabled: Bool = true
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    @AppStorage("browserOrder") private var browserOrder: [String] = []

    @State private var hasDetected = false
    @State private var detectionError: String?

    private func move(from source: IndexSet, to destination: Int) {
        browserOrder = BrowserOrder.move(
            browserOrder,
            visibleKeys: browserItems.map(\.orderKey),
            from: source,
            to: destination
        )
    }

    private func privateArg(for key: String) -> Binding<String> {
        return .init(
            get: { self.privateArgs[key, default: ""] },
            set: { self.privateArgs[key] = $0 })
    }

    private var chromeInstalled: Bool {
        ChromeProfileUtil.chromeURL() != nil
    }

    private var pickerBrowsers: [PickerBrowser] {
        browsers.compactMap { browser in
            guard let bundle = Bundle(url: browser),
                  let bundleIdentifier = bundle.bundleIdentifier
            else {
                return nil
            }

            return PickerBrowser(
                appURL: browser,
                bundleIdentifier: bundleIdentifier,
                displayName: bundle.infoDictionary?["CFBundleName"] as? String ?? bundleIdentifier
            )
        }
    }

    private var browserItems: [PickerBrowserItem] {
        PickerBrowserItemBuilder.makeItems(
            browsers: pickerBrowsers,
            chromeProfilesEnabled: chromeProfilesEnabled,
            chromeProfiles: chromeProfiles,
            shortcuts: shortcuts,
            browserOrder: browserOrder,
            includeHiddenProfiles: true
        )
    }

    private var browserKeys: [String] {
        pickerBrowsers.map { $0.appURL.absoluteString }
    }

    private var chromeBrowserKeys: [String] {
        pickerBrowsers
            .filter { $0.bundleIdentifier == ChromeProfileUtil.chromeBundleID }
            .map { $0.appURL.absoluteString }
    }

    private func normalizeOrder(profiles: [ChromeProfile]? = nil) {
        let profileKeys = (profiles ?? chromeProfiles)
            .map { "\(ChromeProfileUtil.chromeBundleID)::\($0.directoryName)" }
        browserOrder = BrowserOrder.merge(
            existing: browserOrder,
            browserKeys: browserKeys,
            chromeBrowserKeys: chromeBrowserKeys,
            profileKeys: profileKeys
        )
    }

    private func detectProfiles() {
        do {
            var merged = try ChromeProfileUtil.refreshProfiles(current: chromeProfiles) {
                try ChromeProfileUtil.detectProfiles()
            }

            if browsers.contains(where: { browser in
                chromeBrowserKeys.contains(browser.absoluteString) && hiddenBrowsers.contains(browser)
            }) {
                merged = merged.map {
                    ChromeProfile(
                        directoryName: $0.directoryName,
                        displayName: $0.displayName,
                        isHidden: true
                    )
                }
                hiddenBrowsers.removeAll { chromeBrowserKeys.contains($0.absoluteString) }
            }

            ChromeProfileUtil.migrateLegacyShortcut(&shortcuts, to: merged)
            chromeProfiles = merged
            normalizeOrder(profiles: merged)
            detectionError = nil
        } catch {
            detectionError = "Could not read Chrome profiles. Your saved profile settings were not changed."
        }
        hasDetected = true
    }

    private func profileName(for directoryName: String) -> Binding<String> {
        Binding(
            get: { chromeProfiles.first(where: { $0.directoryName == directoryName })?.displayName ?? "" },
            set: { name in
                guard let index = chromeProfiles.firstIndex(where: { $0.directoryName == directoryName }) else {
                    return
                }
                chromeProfiles[index].displayName = name
            }
        )
    }

    private func isProfileHidden(_ directoryName: String) -> Bool {
        chromeProfiles.first(where: { $0.directoryName == directoryName })?.isHidden ?? false
    }

    private func toggleProfileVisibility(_ directoryName: String) {
        guard let index = chromeProfiles.firstIndex(where: { $0.directoryName == directoryName }) else {
            return
        }
        chromeProfiles[index].isHidden.toggle()
    }

    var body: some View {
        VStack(alignment: .leading) {
            if chromeInstalled {
                HStack(spacing: 16) {
                    Toggle(isOn: $chromeProfilesEnabled) {
                        Text("Show Chrome profiles as browser items")
                            .font(.callout)
                    }

                    Spacer()

                    Button(action: detectProfiles) {
                        Text("Detect Profiles")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                TextField(
                    "Chrome private argument",
                    text: privateArg(for: ChromeProfileUtil.chromeBundleID)
                )
                .font(.system(size: 14).monospaced())
                .padding(.horizontal, 20)

                if let detectionError {
                    Text(detectionError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
            }

            List {
                ForEach(Array(browserItems.enumerated()), id: \.element.id) { offset, item in
                    if let bundle = Bundle(url: item.appURL) {
                        HStack {
                            Text((offset + 1).formatted())
                                .font(
                                    .system(size: 16)
                                )
                                .frame(width: 30, alignment: .leading)

                            ZStack(alignment: .bottomTrailing) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: bundle.bundlePath))
                                    .resizable()
                                    .frame(width: 32, height: 32)

                                if item.profileDirectory != nil {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .background(Circle().fill(.background))
                                }
                            }

                            Spacer()
                                .frame(width: 8)

                            if let directoryName = item.profileDirectory {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("Profile name", text: profileName(for: directoryName))
                                        .font(.system(size: 14))

                                    Text("Browser profile · \(directoryName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(bundle.infoDictionary!["CFBundleName"] as! String)
                                    .font(.system(size: 14))
                            }

                            Spacer()
                                .frame(width: 32)

                            if item.profileDirectory == nil {
                                TextField(
                                    "Private argument",
                                    text: privateArg(for: bundle.bundleIdentifier!)
                                )
                                .font(.system(size: 14).monospaced())
                            }

                            Spacer()
                                .frame(width: 32)

                            ShortcutButton(
                                browserId: item.profileDirectory == nil
                                    ? bundle.bundleIdentifier!
                                    : item.orderKey
                            )

                            Spacer()
                                .frame(width: 8)

                            Button(action: {
                                if let directoryName = item.profileDirectory {
                                    toggleProfileVisibility(directoryName)
                                } else if let idx = hiddenBrowsers.firstIndex(of: item.appURL) {
                                    hiddenBrowsers.remove(at: idx)
                                } else {
                                    hiddenBrowsers.append(item.appURL)
                                }
                            }) {
                                Image(
                                    systemName: (item.profileDirectory.map(isProfileHidden) ?? hiddenBrowsers.contains(item.appURL))
                                        ? "eye.slash.fill" : "eye.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                    }
                }
                .onMove(perform: move)
            }
            .onAppear {
                if browsers.isEmpty {
                    browsers = BrowserUtil.loadBrowsers(
                        oldBrowsers: browsers
                    )
                }

                if !hasDetected && chromeInstalled && chromeProfiles.isEmpty {
                    detectProfiles()
                } else {
                    ChromeProfileUtil.migrateLegacyShortcut(&shortcuts, to: chromeProfiles)
                    normalizeOrder()
                }
            }
            .onChange(of: chromeProfilesEnabled) { _ in
                normalizeOrder()
            }

            Text(
                "Drag and drop to reorder. Profile rows can be placed anywhere. Press record to assign a shortcut and click the eye to hide an item."
            )
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    PreferencesView()
}
