//
//  CartoucheIPhoneAppList.swift
//  Cartouche
//
//  The apps Cartouche installed on this iPhone through the built-in
//  SideStore, as apps of their own (decision 88): the list Cartouche keeps
//  in the app group (CartoucheInstalledApps, which SideStore's patch 0022
//  writes), joined with what SideStore records of every installed app for
//  its widget (widget_data.json), as CartoucheSignature reads Cartouche's
//  own expiry from it. Pure: CartoucheIPhoneApps reads the files and runs
//  the actions.
//

import Foundation

struct CartoucheIPhoneApp: Identifiable, Equatable, Sendable {
    let name: String
    let bundleIdentifier: String
    /// The identifier SideStore signed the app under, which opens it.
    let resignedBundleIdentifier: String
    let expirationDate: Date?
    let refreshedDate: Date?
    /// Whole days left before the signature expires, 0 on the last day,
    /// negative once expired; nil while SideStore recorded no expiry.
    let daysLeft: Int?

    var id: String { bundleIdentifier }
    var isExpired: Bool { (daysLeft ?? 0) < 0 }
    /// The link iOS opens the app by: the scheme SideStore adds to every app
    /// it signs (InstalledApp.openAppURL).
    var openURL: URL { URL(string: "sidestore-\(resignedBundleIdentifier)://") ?? URL(fileURLWithPath: "/") }
}

enum CartoucheIPhoneAppList {
    /// SideStore's record of its installed apps, as its widget reads it:
    /// dates as JSONEncoder writes them.
    private struct WidgetData: Decodable {
        struct App: Decodable {
            let name: String?
            let bundleIdentifier: String
            let expirationDate: Date
            let refreshedDate: Date
        }
        let allApps: [App]
    }

    /// The apps on LISTED, in its order, each with what WIDGETDATA records
    /// of it, nothing when it records nothing or cannot be read.
    static func apps(listed: [[String: String]], widgetData: Data?, now: Date = Date()) -> [CartoucheIPhoneApp] {
        let recorded = widgetData.flatMap { try? JSONDecoder().decode(WidgetData.self, from: $0) }?.allApps ?? []
        let byIdentifier = Dictionary(recorded.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { _, last in last })
        return listed.compactMap { entry in
            guard let identifier = entry["bundleIdentifier"], !identifier.isEmpty else { return nil }
            let record = byIdentifier[identifier]
            let expiration = record?.expirationDate
            return CartoucheIPhoneApp(
                name: entry["name"].flatMap { $0.isEmpty ? nil : $0 } ?? record?.name ?? identifier,
                bundleIdentifier: identifier,
                resignedBundleIdentifier: entry["resignedBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 } ?? identifier,
                expirationDate: expiration,
                refreshedDate: record?.refreshedDate,
                daysLeft: expiration.map { Int(floor($0.timeIntervalSince(now) / 86_400)) })
        }
    }

    static func soonestExpiry(of apps: [CartoucheIPhoneApp]) -> Date? {
        apps.compactMap(\.expirationDate).min()
    }

    /// Removes the copies of IPAs older than AGE in FOLDER: an install
    /// deletes its own copy (CartoucheInstallAppIntent), a Cartouche killed
    /// as it copied leaves one.
    static func removeLeftoverIPAs(in folder: URL, olderThan age: TimeInterval = 3_600, now: Date = Date()) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > age { try? manager.removeItem(at: item) }
        }
    }

    /// The bundle identifiers SideStore's outcome names as failed, "a,b":
    /// those that read as one.
    static func failedIdentifiers(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && CartoucheFailure.isDomain($0) }
    }
}
