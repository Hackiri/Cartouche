//
//  CartoucheIPhoneApps.swift
//  Cartouche
//
//  The apps Cartouche installed on this iPhone through the built-in
//  SideStore, as apps of their own, and what the System page does with them
//  (decision 88): install an IPA, renew one, uninstall one, open one. Each
//  action is SideStore's, run headless in LiveProcess through LiveContainer's
//  bridge (CartoucheApps, launcher/SideStoreSupport; app/patches/sidestore/
//  0022), with its request left in the app group defaults first and how it
//  ended read from the keychain item SideStore leaves (CartoucheSideStoreOutcome),
//  as Renew now runs Refresh All Apps (CartoucheRenewal). The list of the
//  apps is SideStore's to keep (CartoucheInstalledApps); what each app's
//  signature is comes from SideStore's record for its widget
//  (CartoucheIPhoneAppList).
//

import Foundation
import UIKit

@available(iOS 17.0, *)
@MainActor
final class CartoucheIPhoneApps: ObservableObject {
    static let shared = CartoucheIPhoneApps()

    /// The action under way, one at a time: the bridge takes one.
    struct Work: Equatable {
        enum Kind: Equatable {
            case installing(String), renewing(String), removing(String)
        }
        let kind: Kind
        let progress: Progress

        var name: String {
            switch kind {
            case .installing(let name), .renewing(let name), .removing(let name): return name
            }
        }
        /// Which app's row shows it: nil for an install.
        var bundleIdentifier: String? {
            switch kind {
            case .installing: return nil
            case .renewing(let identifier), .removing(let identifier): return identifier
            }
        }
    }

    @Published private(set) var apps: [CartoucheIPhoneApp] = []
    @Published private(set) var work: Work?
    /// Why the last action on each app failed, by bundle identifier; under
    /// `installFailure` for the last install.
    @Published private(set) var failures: [String: CartoucheReport] = [:]

    static let installFailure = ""
    /// Where SideStore's patch keeps the list, and where the launcher leaves
    /// a request (CartoucheAppsRequest.swift).
    static let listKey = "CartoucheInstalledApps"
    static let requestKey = "CartoucheAppsRequest"

    // MARK: The bridge

    private typealias Call = @convention(c) (
        AnyObject, Selector, Progress, @escaping @convention(block) (NSString?) -> Void) -> Void

    private static let installSelector = NSSelectorFromString("installAppWithProgress:completion:")
    private static let refreshSelector = NSSelectorFromString("refreshAppsWithProgress:completion:")
    private static let removeSelector = NSSelectorFromString("removeAppWithProgress:completion:")

    /// CartoucheApps is in SideStoreSupport, which LiveContainer loads only
    /// when the app carries the built-in SideStore.
    private static func method(_ selector: Selector) -> (receiver: AnyObject, call: Call)? {
        guard let bridge = NSClassFromString("CartoucheApps"),
              let method = class_getClassMethod(bridge, selector) else { return nil }
        return (bridge as AnyObject, unsafeBitCast(method_getImplementation(method), to: Call.self))
    }

    static var isAvailable: Bool { unavailableReason == nil }

    /// Whether the built-in SideStore works for Renew now or an update:
    /// the bridge takes one action at a time (RefreshHandler), and those
    /// two wait for this model's in turn (CartoucheSystemView).
    static var isBusyElsewhere: Bool { CartoucheRenewal.isRenewing || CartoucheUpdates.shared.phase != nil }

    /// Why nothing can be installed: a p12 and its profile sign Cartouche
    /// alone (decision 78), or the bridge did not load.
    static var unavailableReason: String? {
        if CartoucheImportedSigning.accountSigningDisabled { return CartoucheText.signingUpdateOnComputer }
        #if !CARTOUCHE_GALLERY
        // The gallery has no bridge: its section shows all the same.
        if method(installSelector) == nil { return CartoucheText.renewUnavailable }
        #endif
        return nil
    }

    // MARK: What is installed

    static var listed: [[String: String]] {
        LCUtils.appGroupUserDefault.array(forKey: listKey) as? [[String: String]] ?? []
    }

    private static var widgetData: URL? { LCSharedUtils.appGroupPath()?.appendingPathComponent("widget_data.json") }

    /// Where an IPA waits for its install, in the app group LiveProcess reads.
    private static var installs: URL? {
        LCSharedUtils.appGroupPath()?.appendingPathComponent("Cartouche/Installs", isDirectory: true)
    }

    private var lastReload = Date.distantPast

    /// Reads the list and SideStore's record again, sweeps the IPAs an
    /// install left, and takes what a renewal without a screen, the nightly
    /// one, left of the apps that failed. Once every two seconds at most,
    /// unless FORCED: the System page asks at each return to it. The files
    /// and the keychain are read off the main thread, which the console's
    /// watch holds to a few hundred milliseconds.
    func reload(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastReload) > 2 else { return }
        lastReload = Date()
        let listed = Self.listed
        let widgetData = Self.widgetData
        let installs = Self.installs
        Task.detached(priority: .userInitiated) { [weak self] in
            let fresh = CartoucheIPhoneAppList.apps(listed: listed, widgetData: widgetData.flatMap { try? Data(contentsOf: $0) })
            if let installs { CartoucheIPhoneAppList.removeLeftoverIPAs(in: installs) }
            // A Refresh All Apps that ended with no one to read it, the
            // Shortcuts automation's: its outcome waits in the keychain.
            // Renew now reads its own within seconds (CartoucheRenewal), so
            // only one older than two minutes is a night's; nothing to
            // attribute it to without apps.
            let nightly = listed.isEmpty ? nil : Self.takeNightlyOutcomeFromKeychain()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if fresh != self.apps { self.apps = fresh }
                if let nightly { self.noteRenewal(outcome: nightly, message: nil) }
            }
        }
    }

    /// The outcome a Refresh All Apps left with no one to read it, taken:
    /// older than two minutes, so Renew now's own, read within seconds
    /// (CartoucheRenewal), is never mistaken for it.
    nonisolated private static func takeNightlyOutcomeFromKeychain() -> CartoucheSideStoreOutcome? {
        guard let data = CartoucheStoreKeychain.data(CartoucheSideStoreOutcome.account),
              let outcome = CartoucheSideStoreOutcome(data: data, expecting: .refresh, maximumAge: 86_400),
              Date().timeIntervalSince(outcome.date) > 120 else { return nil }
        CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)
        return outcome
    }

    /// Takes a night's outcome now, on the main thread: Renew now calls it
    /// before it clears the keychain item for its own.
    func takeNightlyOutcome() {
        guard !Self.listed.isEmpty, let outcome = Self.takeNightlyOutcomeFromKeychain() else { return }
        noteRenewal(outcome: outcome, message: nil)
    }

    /// The apps of Cartouche's that OUTCOME, a Refresh All Apps', names as
    /// failed: each row shows it, with MESSAGE when the renewal said why.
    /// Named from the list in the app group, which is there before this
    /// model ever loaded its apps.
    func noteRenewal(outcome: CartoucheSideStoreOutcome?, message: String?) {
        guard let outcome, !outcome.failedApps.isEmpty else { return }
        let named = CartoucheIPhoneAppList.apps(listed: Self.listed, widgetData: nil)
        for app in named where outcome.failedApps.contains(app.bundleIdentifier) {
            let failure = CartoucheFailure.sideStore(outcome: outcome, message: message, fraction: nil,
                                                     seconds: outcome.seconds.map(Double.init),
                                                     vpn: CartoucheVPN.isConnected, pairing: CartouchePairing.exists)
            failures[app.bundleIdentifier] = CartoucheReports.make(
                .apps, CartoucheText.appsFailedRenew(app.name),
                message: message.map { CartoucheText.sideStoreMessage($0, failure: failure) } ?? CartoucheText.renewFailed,
                stage: outcome.stage, failure: failure)
        }
    }

    // MARK: The actions

    /// Copies the IPA at URL, picked in Files, into the app group and has
    /// SideStore install it as an app of its own.
    func install(ipa url: URL) async {
        guard let method = Self.method(Self.installSelector), let installs = Self.installs else {
            failures[Self.installFailure] = busy(CartoucheText.appsFailedInstall, message: Self.unavailableReason ?? CartoucheText.renewUnavailable)
            return
        }
        guard work == nil, !Self.isBusyElsewhere else {
            failures[Self.installFailure] = busy(CartoucheText.appsFailedInstall, message: CartoucheText.appsBusy)
            return
        }
        failures[Self.installFailure] = nil
        let name = url.deletingPathExtension().lastPathComponent
        let progress = Progress(totalUnitCount: 100)
        let started = Date()
        work = Work(kind: .installing(name), progress: progress)
        defer {
            work = nil
            reload(force: true)
        }
        CartoucheReports.note("Apps on this iPhone: installing \(name)")
        let copy = installs.appendingPathComponent(UUID().uuidString + ".ipa")
        do {
            let reachable = url.startAccessingSecurityScopedResource()
            defer { if reachable { url.stopAccessingSecurityScopedResource() } }
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: installs, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: copy)
            }.value
            LCUtils.appGroupUserDefault.set(["ipa": copy.path], forKey: Self.requestKey)
        } catch {
            failures[Self.installFailure] = CartoucheReports.make(.apps, CartoucheText.appsFailedInstall,
                                                                  message: error.localizedDescription, error: error)
            return
        }
        let message = await call(method, Self.installSelector, progress)
        let outcome = Self.takeOutcome().flatMap { CartoucheSideStoreOutcome(data: $0, expecting: .install) }
        if let message {
            // The intent deletes the copy once it ran; one that never started,
            // the bridge busy, leaves it and the request.
            try? FileManager.default.removeItem(at: copy)
            LCUtils.appGroupUserDefault.removeObject(forKey: Self.requestKey)
            failures[Self.installFailure] = failed(CartoucheText.appsFailedInstall, message: message, outcome: outcome,
                                                   progress: progress, started: started)
        } else {
            CartoucheReports.note("Apps on this iPhone: \(name) installed")
        }
    }

    /// Renews APP's signature.
    func renew(_ app: CartoucheIPhoneApp) async {
        guard let method = Self.method(Self.refreshSelector), work == nil, !Self.isBusyElsewhere else {
            failures[app.bundleIdentifier] = busy(CartoucheText.appsFailedRenew(app.name),
                                                  message: Self.unavailableReason ?? CartoucheText.appsBusy)
            return
        }
        failures[app.bundleIdentifier] = nil
        let progress = Progress(totalUnitCount: 100)
        let started = Date()
        work = Work(kind: .renewing(app.bundleIdentifier), progress: progress)
        defer {
            work = nil
            reload(force: true)
        }
        LCUtils.appGroupUserDefault.set(["apps": [app.bundleIdentifier]], forKey: Self.requestKey)
        let message = await call(method, Self.refreshSelector, progress)
        let outcome = Self.takeOutcome().flatMap { CartoucheSideStoreOutcome(data: $0, expecting: .apps) }
        if let message {
            failures[app.bundleIdentifier] = failed(CartoucheText.appsFailedRenew(app.name), message: message,
                                                    outcome: outcome, progress: progress, started: started)
        }
    }

    /// Uninstalls APP from this iPhone, or clears what SideStore kept of an
    /// app already gone from the home screen.
    func remove(_ app: CartoucheIPhoneApp) async {
        guard let method = Self.method(Self.removeSelector), work == nil, !Self.isBusyElsewhere else {
            failures[app.bundleIdentifier] = busy(CartoucheText.appsFailedRemove(app.name),
                                                  message: Self.unavailableReason ?? CartoucheText.appsBusy)
            return
        }
        failures[app.bundleIdentifier] = nil
        let progress = Progress(totalUnitCount: 100)
        let started = Date()
        work = Work(kind: .removing(app.bundleIdentifier), progress: progress)
        defer {
            work = nil
            reload(force: true)
        }
        LCUtils.appGroupUserDefault.set(["app": app.bundleIdentifier], forKey: Self.requestKey)
        let message = await call(method, Self.removeSelector, progress)
        let outcome = Self.takeOutcome().flatMap { CartoucheSideStoreOutcome(data: $0, expecting: .remove) }
        if let message {
            failures[app.bundleIdentifier] = failed(CartoucheText.appsFailedRemove(app.name), message: message,
                                                    outcome: outcome, progress: progress, started: started)
        }
    }

    /// Opens APP on the home screen: false when iOS has no such app any
    /// more, or its signature is gone.
    func open(_ app: CartoucheIPhoneApp) async -> Bool {
        await UIApplication.shared.open(app.openURL)
    }

    // MARK: How an action ends

    private func call(_ method: (receiver: AnyObject, call: Call), _ selector: Selector, _ progress: Progress) async -> String? {
        CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)
        return await withCheckedContinuation { continuation in
            method.call(method.receiver, selector, progress) { message in
                continuation.resume(returning: message.map { $0 as String })
            }
        }
    }

    /// What SideStore left of the action, taken.
    private static func takeOutcome() -> Data? {
        let data = CartoucheStoreKeychain.data(CartoucheSideStoreOutcome.account)
        CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)
        return data
    }

    private func busy(_ title: String, message: String) -> CartoucheReport {
        CartoucheReports.make(.apps, title, message: message)
    }

    /// The report on an action that failed: Cartouche's own words for what
    /// it refused, SideStore's, made readable, for the rest.
    private func failed(_ title: String, message: String, outcome: CartoucheSideStoreOutcome?, progress: Progress,
                        started: Date) -> CartoucheReport {
        let seconds = Date().timeIntervalSince(started)
        let failure = CartoucheFailure.sideStore(outcome: outcome, message: message, fraction: progress.fractionCompleted,
                                                 seconds: seconds, vpn: CartoucheVPN.isConnected, pairing: CartouchePairing.exists)
        let words: String
        switch (outcome?.family, outcome?.kind) {
        case ("cartouche"?, "anotherStoresApp"?): words = CartoucheText.appsErrorAnotherStore
        case ("cartouche"?, "appLimit"?): words = CartoucheText.appsErrorLimit
        default: words = CartoucheText.sideStoreMessage(message, failure: failure)
        }
        CartoucheReports.note("Apps on this iPhone: \(title): \(failure.cause.rawValue)")
        return CartoucheReports.make(.apps, title, message: words, fraction: progress.fractionCompleted,
                                     stage: outcome?.stage, seconds: seconds, failure: failure)
    }
}
