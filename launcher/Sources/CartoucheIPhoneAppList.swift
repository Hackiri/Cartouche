//
//  CartoucheIPhoneAppList.swift
//  Cartouche
//
//  The apps Cartouche installed on this iPhone through the built-in
//  SideStore, as apps of their own (decision 137): the list Cartouche keeps
//  in the app group (CartoucheInstalledApps, which SideStore's patch 0027
//  writes), joined with what SideStore records of every installed app for
//  its widget (widget_data.json), as CartoucheSignature reads Cartouche's
//  own expiry from it; and the App IDs Apple keeps for the Apple ID, as
//  SideStore's patch 0028 leaves them in the app group. Pure:
//  CartoucheIPhoneApps reads the files and runs the actions.
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

/// An App ID Apple keeps for the Apple ID, as SideStore's App IDs page lists
/// them and CartoucheAppIDsIntent writes them (app/patches/sidestore/0028).
struct CartoucheAppID: Identifiable, Equatable, Sendable {
    let name: String
    /// Apple's own, ten characters.
    let identifier: String
    let bundleIdentifier: String
    /// A week after a free Apple ID registered it; nil for a paid team's,
    /// which never expire.
    let expirationDate: Date?

    var id: String { identifier }
}

/// The App IDs as last fetched, and when.
struct CartoucheAppIDListing: Equatable, Sendable {
    let date: Date
    let appIDs: [CartoucheAppID]
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

    /// What CartoucheAppIDsIntent leaves in the app group: dates in seconds
    /// since 1970.
    private struct WrittenAppIDs: Decodable {
        struct Entry: Decodable {
            let name: String?
            let identifier: String
            let bundleIdentifier: String?
            let expirationDate: Date?
        }
        let date: Date
        let appIDs: [Entry]
    }

    /// The App IDs in DATA, the one that expires first first and those
    /// without a date last, at most 500 of them, each text cut to 256
    /// characters; nil without a list, or one that cannot be read, is from
    /// the future or is over a year old.
    static func appIDs(data: Data?, now: Date = Date()) -> CartoucheAppIDListing? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let written = try? decoder.decode(WrittenAppIDs.self, from: data),
              written.date <= now.addingTimeInterval(300), now.timeIntervalSince(written.date) <= 366 * 86_400 else { return nil }
        func cut(_ text: String?) -> String { String((text ?? "").prefix(256)) }
        let appIDs = written.appIDs.prefix(500).compactMap { entry -> CartoucheAppID? in
            let identifier = cut(entry.identifier)
            guard !identifier.isEmpty else { return nil }
            return CartoucheAppID(name: cut(entry.name), identifier: identifier, bundleIdentifier: cut(entry.bundleIdentifier),
                                  expirationDate: entry.expirationDate)
        }
        .sorted { first, second in
            switch (first.expirationDate, second.expirationDate) {
            case let (one?, other?) where one != other: return one < other
            case (nil, _?): return false
            case (_?, nil): return true
            default: return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
        }
        return CartoucheAppIDListing(date: written.date, appIDs: appIDs)
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
