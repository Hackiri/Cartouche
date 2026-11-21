//
//  CartoucheIPhoneAppListTests.swift
//  CartoucheCoreTests
//
//  The apps Cartouche installed on this iPhone, as the System page lists
//  them (Sources/CartoucheIPhoneAppList.swift): the list Cartouche keeps in
//  the app group joined with what SideStore records of every installed app
//  for its widget, the days left before each expires, the link that opens
//  one, the leftovers an install may leave, and the App IDs Apple keeps for
//  the Apple ID as SideStore's patch 0028 leaves them.
//

import Foundation
import XCTest
@testable import CartoucheCore

final class CartoucheIPhoneAppListTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let listed: [[String: String]] = [
        ["bundleIdentifier": "com.utmapp.UTM", "resignedBundleIdentifier": "com.utmapp.UTM.ABCDE12345", "name": "UTM"],
        ["bundleIdentifier": "com.rileytestut.Delta", "resignedBundleIdentifier": "com.rileytestut.Delta.ABCDE12345", "name": "Delta"],
    ]

    /// SideStore's widget_data.json, dates as JSONEncoder writes them.
    private func widgetData(_ apps: [(name: String, id: String, expires: TimeInterval, refreshed: TimeInterval)]) throws -> Data {
        let items: [[String: Any]] = apps.map {
            ["name": $0.name, "bundleIdentifier": $0.id,
             "expirationDate": now.addingTimeInterval($0.expires).timeIntervalSinceReferenceDate,
             "refreshedDate": now.addingTimeInterval($0.refreshed).timeIntervalSinceReferenceDate]
        }
        return try JSONSerialization.data(withJSONObject: ["activeApps": items, "allApps": items,
                                                           "lastUpdated": now.timeIntervalSinceReferenceDate])
    }

    func testAppsJoinTheListWithTheWidgetDataByIdentifier() throws {
        let data = try widgetData([("UTM", "com.utmapp.UTM", 3.5 * 86_400, -86_400),
                                   ("Other", "com.example.other", 86_400, -3_600)])
        let apps = CartoucheIPhoneAppList.apps(listed: listed, widgetData: data, now: now)
        XCTAssertEqual(apps.map(\.bundleIdentifier), ["com.utmapp.UTM", "com.rileytestut.Delta"])
        XCTAssertEqual(apps[0].name, "UTM")
        XCTAssertEqual(apps[0].daysLeft, 3)
        XCTAssertEqual(apps[0].expirationDate, now.addingTimeInterval(3.5 * 86_400))
        XCTAssertEqual(apps[0].refreshedDate, now.addingTimeInterval(-86_400))
        XCTAssertNil(apps[1].expirationDate)
        XCTAssertNil(apps[1].refreshedDate)
        XCTAssertNil(apps[1].daysLeft)
    }

    func testDaysLeftIsZeroOnTheLastDayAndNegativeOnceExpired() throws {
        let data = try widgetData([("UTM", "com.utmapp.UTM", 3_600, -86_400),
                                   ("Delta", "com.rileytestut.Delta", -3_600, -86_400)])
        let apps = CartoucheIPhoneAppList.apps(listed: listed, widgetData: data, now: now)
        XCTAssertEqual(apps[0].daysLeft, 0)
        XCTAssertFalse(apps[0].isExpired)
        XCTAssertEqual(apps[1].daysLeft, -1)
        XCTAssertTrue(apps[1].isExpired)
    }

    func testTheOpenURLUsesTheResignedIdentifier() {
        let apps = CartoucheIPhoneAppList.apps(listed: listed, widgetData: nil, now: now)
        XCTAssertEqual(apps[0].openURL.absoluteString, "sidestore-com.utmapp.UTM.ABCDE12345://")
    }

    func testSoonestExpiryIgnoresAppsWithoutADate() throws {
        let data = try widgetData([("Delta", "com.rileytestut.Delta", 2 * 86_400, -86_400)])
        let apps = CartoucheIPhoneAppList.apps(listed: listed, widgetData: data, now: now)
        XCTAssertEqual(CartoucheIPhoneAppList.soonestExpiry(of: apps), now.addingTimeInterval(2 * 86_400))
        let undated = CartoucheIPhoneAppList.apps(listed: listed, widgetData: nil, now: now)
        XCTAssertNil(CartoucheIPhoneAppList.soonestExpiry(of: undated))
    }

    func testBrokenWidgetDataLeavesTheListWithoutDates() {
        let apps = CartoucheIPhoneAppList.apps(listed: listed, widgetData: Data("{".utf8), now: now)
        XCTAssertEqual(apps.count, 2)
        XCTAssertNil(apps[0].expirationDate)
    }

    func testLeftoverIPAsOlderThanAnHourAreRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("old.ipa")
        let fresh = folder.appendingPathComponent("fresh.ipa")
        try Data("a".utf8).write(to: old)
        try Data("b".utf8).write(to: fresh)
        let realNow = Date()
        try FileManager.default.setAttributes([.modificationDate: realNow.addingTimeInterval(-7_200)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: realNow.addingTimeInterval(-600)], ofItemAtPath: fresh.path)
        CartoucheIPhoneAppList.removeLeftoverIPAs(in: folder, olderThan: 3_600, now: realNow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testFailedIdentifiersAreSplitOnCommas() {
        XCTAssertEqual(CartoucheIPhoneAppList.failedIdentifiers("a.b, c.d,,"), ["a.b", "c.d"])
        XCTAssertEqual(CartoucheIPhoneAppList.failedIdentifiers(nil), [])
    }

    /// Cartouche/AppIDs.json as CartoucheAppIDsIntent writes it, dates in
    /// seconds since 1970.
    private func appIDsData(date: TimeInterval, _ appIDs: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["date": now.addingTimeInterval(date).timeIntervalSince1970, "appIDs": appIDs])
    }

    func testAppIDsComeTheOneThatExpiresFirstFirstAndThoseWithoutADateLast() throws {
        let data = try appIDsData(date: -60, [
            ["name": "Delta", "identifier": "ABCDE12345", "bundleIdentifier": "com.rileytestut.Delta.T1",
             "expirationDate": now.addingTimeInterval(5 * 86_400).timeIntervalSince1970],
            ["name": "Paid", "identifier": "KLMNO13579", "bundleIdentifier": "com.example.paid"],
            ["name": "UTM", "identifier": "FGHIJ67890", "bundleIdentifier": "com.utmapp.UTM.T1",
             "expirationDate": now.addingTimeInterval(86_400).timeIntervalSince1970],
            ["name": "", "identifier": "", "bundleIdentifier": "com.example.none"],
        ])
        let listing = try XCTUnwrap(CartoucheIPhoneAppList.appIDs(data: data, now: now))
        XCTAssertEqual(listing.date, now.addingTimeInterval(-60))
        XCTAssertEqual(listing.appIDs.map(\.identifier), ["FGHIJ67890", "ABCDE12345", "KLMNO13579"])
        XCTAssertEqual(listing.appIDs[0].name, "UTM")
        XCTAssertEqual(listing.appIDs[0].bundleIdentifier, "com.utmapp.UTM.T1")
        XCTAssertEqual(listing.appIDs[0].expirationDate, now.addingTimeInterval(86_400))
        XCTAssertNil(listing.appIDs[2].expirationDate)
    }

    func testAppIDsFromTheFutureOrUnreadableAreNoList() throws {
        XCTAssertNil(CartoucheIPhoneAppList.appIDs(data: nil, now: now))
        XCTAssertNil(CartoucheIPhoneAppList.appIDs(data: Data("{".utf8), now: now))
        XCTAssertNil(CartoucheIPhoneAppList.appIDs(data: try appIDsData(date: 3_600, []), now: now))
        XCTAssertNil(CartoucheIPhoneAppList.appIDs(data: try appIDsData(date: -400 * 86_400, []), now: now))
        XCTAssertEqual(CartoucheIPhoneAppList.appIDs(data: try appIDsData(date: 0, []), now: now)?.appIDs, [])
    }
}
