//
//  CartoucheApps.swift
//  Cartouche
//
//  Lets Cartouche install an IPA as an app of its own on this iPhone, renew
//  the apps it installed that way and uninstall them, without showing
//  SideStore (decision 88). The built-in SideStore starts in LiveProcess, as
//  it does to renew the app (CartoucheRefresh), and runs the action
//  app/patches/sidestore/0022 adds; what the action works on, the IPA's
//  path in the app group or the apps' bundle identifiers, waits in the app
//  group defaults under CartoucheAppsRequest, written by the launcher
//  before the call (CartoucheIPhoneApps). One action at a time: the
//  bridge's RefreshHandler takes one.
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
        run(progress: progress, completion: completion) {
            try await performIntentRefresh(identifier: "CartoucheInstallAppIntent",
                                           mangledTypeName: "9SideStore25CartoucheInstallAppIntentV", intentProgress: progress)
        }
    }

    /// Renews the apps the request names.
    @objc(refreshAppsWithProgress:completion:)
    public static func refreshApps(progress: Progress, completion: @escaping (String?) -> Void) {
        run(progress: progress, completion: completion) {
            try await performIntentRefresh(identifier: "CartoucheRefreshAppsIntent",
                                           mangledTypeName: "9SideStore26CartoucheRefreshAppsIntentV", intentProgress: progress)
        }
    }

    /// Uninstalls the app the request names.
    @objc(removeAppWithProgress:completion:)
    public static func removeApp(progress: Progress, completion: @escaping (String?) -> Void) {
        run(progress: progress, completion: completion) {
            try await performIntentRefresh(identifier: "CartoucheRemoveAppIntent",
                                           mangledTypeName: "9SideStore24CartoucheRemoveAppIntentV", intentProgress: progress)
        }
    }

    /// The names the actions have in SideStore's module: performIntentRefresh
    /// takes them as LiveContainer's own Refresh All Apps intent passes its
    /// own (SideStoreSupport/SideStore.swift).
    private static func run(progress: Progress, completion: @escaping (String?) -> Void,
                            _ action: @escaping @MainActor () async throws -> Void) {
        guard #available(iOS 17.0, *) else {
            completion("Installing apps from Cartouche needs iOS 17 or later.")
            return
        }
        Task { @MainActor in
            do {
                try await action()
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }
}
