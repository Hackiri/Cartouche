//
//  CartoucheAppSettingsView.swift
//  Cartouche
//
//  The settings of an app that is not a game (decision 140): the language it
//  starts in and its orientation, LiveContainer's own settings of the app,
//  which LiveContainer keeps in the app's LCAppInfo.plist and applies the
//  next time the app starts; and whether it needs JIT, with the script
//  StikDebug runs for it from iOS 26 (decision 141). One step further than
//  the app's sheet (CartoucheAppSheetView).
//

import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct CartoucheAppSettingsView: View {
    @ObservedObject var app: LCAppModel
    @State private var choosingScript = false

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
            // StikDebug enables JIT from iOS 17.4.
            if #available(iOS 17.4, *) {
                jitSection
            }
        }
        .scrollContentBackground(.hidden)
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.appSettingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        // The script, as a file StikDebug's own repository gives: kept
        // base64, as LiveContainer's Apps tab keeps it and sends it to
        // StikDebug (LCUtils.askForJIT).
        .fileImporter(isPresented: $choosingScript, allowedContentTypes: [.javaScript, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let reachable = url.startAccessingSecurityScopedResource()
            defer { if reachable { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            app.jitLaunchScriptJs = data.base64EncodedString()
        }
    }

    /// Whether the app needs JIT (LiveContainer's isJITNeeded), and its
    /// JIT script when it does (decision 141).
    private var jitSection: some View {
        Section {
            Toggle(CartoucheText.appNeedsJIT, isOn: $app.uiIsJITNeeded)
            if app.uiIsJITNeeded {
                let loaded = !(app.jitLaunchScriptJs ?? "").isEmpty
                LabeledContent(CartoucheText.appJITScript,
                               value: loaded ? CartoucheText.appJITScriptLoaded : CartoucheText.appJITScriptNone)
                Button(CartoucheText.appJITScriptChoose) { choosingScript = true }
                if loaded {
                    Button(CartoucheText.appJITScriptRemove, role: .destructive) { app.jitLaunchScriptJs = nil }
                }
            }
        } footer: {
            Text(CartoucheText.appJITFooter)
        }
    }
}
