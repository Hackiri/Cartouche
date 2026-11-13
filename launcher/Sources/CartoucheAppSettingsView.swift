//
//  CartoucheAppSettingsView.swift
//  Cartouche
//
//  The settings of an app that is not a game (decision 86): the language it
//  starts in and its orientation, LiveContainer's own settings of the app,
//  which LiveContainer keeps in the app's LCAppInfo.plist and applies the
//  next time the app starts. One step further than the app's sheet
//  (CartoucheAppSheetView).
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheAppSettingsView: View {
    @ObservedObject var app: LCAppModel

    /// The languages the app's bundle has, by their codes: its lproj
    /// folders, as LiveContainer lists them, not what its Info.plist claims.
    private var languages: [String] {
        guard let path = app.appInfo.bundlePath(),
              let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return items.filter { $0.hasSuffix(".lproj") }.map { String($0.dropLast(".lproj".count)) }
            .filter { $0 != "Base" }.sorted()
    }

    var body: some View {
        Form {
            Section {
                Picker(CartoucheText.appLanguage, selection: $app.uiSelectedLanguage) {
                    Text(CartoucheText.appLanguageIPhone).tag("")
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                    }
                }
                Picker(CartoucheText.appOrientation, selection: $app.uiOrientationLock) {
                    Text(CartoucheText.appOrientationAny).tag(LCOrientationLock.Disabled)
                    Text(CartoucheText.appOrientationPortrait).tag(LCOrientationLock.Portrait)
                    Text(CartoucheText.appOrientationLandscape).tag(LCOrientationLock.Landscape)
                }
            } footer: {
                Text(CartoucheText.appSettingsFooter)
            }
        }
        .scrollContentBackground(.hidden)
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.appSettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
