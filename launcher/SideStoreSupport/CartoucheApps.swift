//
//  CartoucheApps.swift
//  Cartouche
//
//  Lets Cartouche install an IPA as an app of its own on this iPhone, renew
//  the apps it installed that way, uninstall them and list the App IDs
//  Apple keeps for the Apple ID, without showing SideStore (decision 125).
//  The built-in SideStore starts in LiveProcess, as it does to renew the
//  app (CartoucheRefresh), and runs the action app/patches/sidestore/0026
//  or 0027 adds; what the action works on, the IPA's path in the app group
//  or the apps' bundle identifiers, waits in the app group defaults under
//  CartoucheAppsRequest, written by the launcher before the call
//  (CartoucheIPhoneApps). One action at a time: the bridge's RefreshHandler
//  takes one.
//
//  This file joins LiveContainer's SideStoreSupport framework, which
//  LiveContainer loads when the app carries the built-in SideStore. The
//  launcher cannot import that framework, so it finds this class by its
//  Objective-C name.
//

import Foundation

@objc(CartoucheApps)
public final class CartoucheApps: NSObject {
    /// Installs the IPA the request names. `progress` counts to 100;
    /// `completion` runs on the main queue, with nil or the error's text.
    @objc(installAppWithProgress:completion:)
    public static func installApp(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else { return completion(tooOld) }
        Task { @MainActor in
            do {
                try await performIntentRefresh(identifier: "CartoucheInstallAppIntent",
                                               mangledTypeName: "9SideStore25CartoucheInstallAppIntentV", intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Renews the apps the request names.
    @objc(refreshAppsWithProgress:completion:)
    public static func refreshApps(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else { return completion(tooOld) }
        Task { @MainActor in
            do {
                try await performIntentRefresh(identifier: "CartoucheRefreshAppsIntent",
                                               mangledTypeName: "9SideStore26CartoucheRefreshAppsIntentV", intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Uninstalls the app the request names.
    @objc(removeAppWithProgress:completion:)
    public static func removeApp(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else { return completion(tooOld) }
        Task { @MainActor in
            do {
                try await performIntentRefresh(identifier: "CartoucheRemoveAppIntent",
                                               mangledTypeName: "9SideStore24CartoucheRemoveAppIntentV", intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Lists the App IDs Apple keeps for the Apple ID, into the app group.
    @objc(fetchAppIDsWithProgress:completion:)
    public static func fetchAppIDs(progress: Progress, completion: @escaping (String?) -> Void) {
        guard #available(iOS 17.0, *) else { return completion(tooOld) }
        Task { @MainActor in
            do {
                try await performIntentRefresh(identifier: "CartoucheAppIDsIntent",
                                               mangledTypeName: "9SideStore21CartoucheAppIDsIntentV", intentProgress: progress)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    private static let tooOld = "Installing apps from Cartouche needs iOS 17 or later."
}
