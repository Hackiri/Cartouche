//
//  CartoucheAppSheetView.swift
//  Cartouche
//
//  The sheet of an app that is not a game, installed in Cartouche as its
//  games are (decision 135): Open, or Resume and Quit while it is paused
//  behind the console; App settings (CartoucheAppSettingsView); what the
//  app says of itself, and the room it takes on this iPhone; and Uninstall,
//  which asks whether its data stays (CartoucheUninstallQuestion). It opens
//  over the console, or beside it on an iPhone Duo, as a game's sheet does
//  (CartoucheGamesView). Nothing of such an app goes into the game
//  measurements.
//

import SwiftUI

@available(iOS 17.0, *)
struct CartoucheAppSheetView: View {
    let entry: CartoucheEntry
    /// Starts the app, or brings it back from behind the console.
    let onOpen: (LCAppModel) -> Void
    /// Opens the app's settings page.
    let onSettings: (LCAppModel) -> Void
    /// Asks whether to uninstall the app, and whether its data stays.
    let onUninstall: (LCAppModel) -> Void
    @ObservedObject private var actions = CartoucheGameActions.shared
    /// The room the app takes, read off the main thread once the sheet shows.
    @State private var size: Int64?

    // Written out: the private state above would make the synthesized
    // initializer private.
    init(entry: CartoucheEntry, onOpen: @escaping (LCAppModel) -> Void, onSettings: @escaping (LCAppModel) -> Void,
         onUninstall: @escaping (LCAppModel) -> Void) {
        self.entry = entry
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.onUninstall = onUninstall
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let app = entry.app {
                Section {
                    if actions.isRunning(app) {
                        Button { onOpen(app) } label: { Label(CartoucheText.resume, systemImage: "play.fill") }
                        Button(role: .destructive) { actions.askToQuit() } label: {
                            Label(CartoucheText.quit, systemImage: "stop.circle")
                        }
                    } else {
                        Button { onOpen(app) } label: { Label(CartoucheText.open, systemImage: "arrow.up.forward.app") }
                    }
                    Button { onSettings(app) } label: {
                        Label(CartoucheText.appSettingsTitle, systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text(CartoucheText.appSheetFooter)
                }
                Section {
                    LabeledContent(CartoucheText.appIdentifier, value: app.appInfo.bundleIdentifier() ?? "")
                    if let version = app.appInfo.version(), !version.isEmpty {
                        LabeledContent(CartoucheText.version, value: version)
                    }
                    if let installed = app.appInfo.installationDate {
                        LabeledContent(CartoucheText.appInstalledOn, value: installed.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let opened = app.appInfo.lastLaunched {
                        LabeledContent(CartoucheText.appLastOpened, value: opened.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let size {
                        LabeledContent(CartoucheText.appSize, value: CartoucheText.storageAmount(bytes: size))
                    }
                }
                // Quit the app first.
                if !actions.isRunning(app) {
                    Section {
                        Button(role: .destructive) { onUninstall(app) } label: {
                            Label(CartoucheText.uninstall, systemImage: "trash")
                                .foregroundStyle(CartoucheTheme.danger)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CartoucheStage(key: entry.tileKey))
        // The header names the app: the bar above it stays empty.
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry.id) {
            guard let app = entry.app else { return }
            size = await CartoucheAppSize.bytes(of: app)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let app = entry.app {
                CartoucheAppIcon(app: app, size: 88, placeholder: "app.fill")
                    .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
            }
            Text(entry.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let app = entry.app, actions.isRunning(app) {
                CartoucheStatusLabel(status: .paused)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// The room an app takes on this iPhone: its bundle and its data folders,
/// those CartoucheGameActions.uninstall removes.
@available(iOS 17.0, *)
enum CartoucheAppSize {
    static func bytes(of app: LCAppModel) async -> Int64? {
        guard let bundle = app.appInfo.bundlePath() else { return nil }
        var folders = [URL(fileURLWithPath: bundle, isDirectory: true)]
        #if !CARTOUCHE_GALLERY
        // Folders the player picked elsewhere are theirs, and not counted.
        folders += app.uiContainers.filter { $0.storageBookMark == nil }.map { container in
            (container.isShared ? LCPath.lcGroupDataPath : LCPath.dataPath).appendingPathComponent(container.folderName)
        }
        #endif
        // Off the main thread, and stopped with the sheet: a data folder
        // can be large.
        let walk = Task.detached(priority: .utility) { () -> Int64 in
            var total: Int64 = 0
            for folder in folders {
                if Task.isCancelled { break }
                total += bytes(under: folder)
            }
            return total
        }
        return await withTaskCancellationHandler {
            await walk.value
        } onCancel: {
            walk.cancel()
        }
    }

    /// The room the files under FOLDER take, as allocated, hidden ones
    /// included; stops early once the task is cancelled.
    nonisolated static func bytes(under folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
