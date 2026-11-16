//
//  AppsUITests.swift
//  CartoucheGalleryUITests
//
//  An app that is not a game, installed in Cartouche (decision 123): on the
//  home's shelf after the games, with Open and Details; its sheet, with App
//  settings, which opens and comes back, whose Needs JIT switch shows the
//  JIT script's row (decision 124), and Uninstall; and the app paused behind
//  the console, which the home offers to resume or to quit.
//

import XCTest

final class AppsUITests: ConsoleTestCase {
    private let app = "UTM:com.utmapp.UTM"
    private let appName = "UTM"

    /// The app's tile is on the home; in focus, the home offers Open and
    /// Details; its sheet has App settings, which opens as a page and comes
    /// back, and Uninstall; Done closes the sheet.
    @MainActor
    func testAnAppOnTheShelfOpensItsSheetSettingsAndComesBack() {
        // One game before it: the app's tile is on screen without a scroll.
        let console = openConsole(Launch(owned: [Games.owned[0]], apps: [app]))
        let tile = console.buttons[appName].firstMatch
        expect(tile.waitForExistence(timeout: 15), "No tile of \(appName) on the home", in: console)
        tap(tile, "The tile of \(appName)", in: console)
        expect(waitUntil(10) { tile.isSelected }, "A tap on \(appName) did not put it in focus", in: console)
        expect(console.buttons[Words.open].waitForExistence(timeout: 10), "The home does not offer Open for \(appName)", in: console)
        tap(console.buttons[Words.details], "Details of \(appName)", in: console)
        expect(sheetShows(appName, in: console), "The sheet open is not \(appName)'s", in: console)
        expect(console.buttons[Words.open].waitForExistence(timeout: 10), "The sheet does not offer Open", in: console)
        let settings = element(in: console.buttons, beginningWith: Words.appSettings)
        scrollTo(settings, "App settings on the sheet", in: console)
        tap(settings, "App settings on the sheet", in: console)
        expect(console.navigationBars[Words.appSettings].waitForExistence(timeout: 15), "App settings did not open", in: console)
        // Needs JIT shows the JIT script's row, and hides it again: its
        // switch itself is tapped, once the rows around it stand still.
        let needsJIT = element(in: console.switches, beginningWith: Words.needsJIT)
        expect(needsJIT.waitForExistence(timeout: 10), "App settings shows no Needs JIT", in: console)
        scrollTo(needsJIT, "Needs JIT in App settings", in: console)
        flip(needsJIT, "Needs JIT", in: console)
        let choose = element(in: console.buttons, beginningWith: Words.jitScriptChoose)
        expect(choose.waitForExistence(timeout: 10), "Needs JIT did not show the JIT script's row", in: console)
        expect(waitUntil(10) { choose.isHittable }, "The JIT script's row does not stand still", in: console)
        flip(needsJIT, "Needs JIT, again", in: console)
        expect(waitForGone(choose), "The JIT script's row stayed once Needs JIT went off", in: console)
        back(from: Words.appSettings, in: console)
        let uninstall = element(in: console.buttons, beginningWith: Words.uninstall)
        scrollTo(uninstall, "Uninstall on the sheet", in: console)
        expect(uninstall.exists, "The sheet does not offer Uninstall", in: console)
        // Done with App settings open: the next sheet opens on the app, not
        // on the settings page left behind.
        tap(settings, "App settings on the sheet, again", in: console)
        expect(console.navigationBars[Words.appSettings].waitForExistence(timeout: 15), "App settings did not open again", in: console)
        closeSheet(in: console)
        tap(console.buttons[Words.details], "Details of \(appName), again", in: console)
        expect(sheetShows(appName, in: console), "The sheet open is not \(appName)'s", in: console)
        expect(console.buttons[Words.open].waitForExistence(timeout: 10),
               "The sheet opened on App settings instead of the app", in: console)
        expect(!console.navigationBars[Words.appSettings].exists, "App settings stayed open from the last sheet", in: console)
        closeSheet(in: console)
        expectMainThreadAnswered(console)
    }

    /// Flips the switch of TOGGLE, a row of a Form, and waits for its value
    /// to change, tapping its switch again, up to three times, should it
    /// not: the simulator drops a tap now and then, as the list under it
    /// still settles after a push or after rows came or went.
    @MainActor
    private func flip(_ toggle: XCUIElement, _ what: String, in app: XCUIApplication,
                      file: StaticString = #filePath, line: UInt = #line) {
        let knob = toggle.switches.firstMatch
        expect(waitUntil(10) { settled(knob) }, "\(what) cannot be tapped yet", in: app, file: file, line: line)
        let before = toggle.value as? String
        for _ in 0..<3 {
            knob.tap()
            if waitUntil(3, { (toggle.value as? String) != before }) { return }
        }
        expect(false, "\(what) did not change in three taps: \(before ?? "no value")", in: app, file: file, line: line)
    }

    /// Whether ELEMENT can be tapped and has stood still for a moment: a tap
    /// on a switch that a row slides past can land beside it.
    @MainActor
    private func settled(_ element: XCUIElement) -> Bool {
        guard element.isHittable else { return false }
        let frame = element.frame
        Thread.sleep(forTimeInterval: 0.3)
        return element.isHittable && element.frame == frame
    }

    /// The app paused behind the console: the home offers Resume and Quit,
    /// and Quit asks first.
    @MainActor
    func testAnAppPausedBehindTheConsoleOffersResumeAndQuit() {
        let console = openConsole(Launch(owned: [Games.owned[0]], apps: [app], work: "paused", sheet: "app:com.utmapp.UTM"))
        expect(console.buttons[Words.resume].waitForExistence(timeout: 15), "The home does not offer to resume \(appName)", in: console)
        expect(console.buttons[Words.quit].exists, "The home does not offer to quit \(appName)", in: console)
        // The console settles first: right after a launch, a tap can land
        // while the home is still laying the shelf out.
        expect(waitUntil(10) { console.buttons[Words.quit].isHittable }, "Quit cannot be tapped yet", in: console)
        tapButtonOnTop(Words.quit, "Quit, for the app paused", in: console)
        let question = String(format: Words.quitQuestion, appName)
        let asked = element(labelled: question, in: console)
        expect(asked.waitForExistence(timeout: 15), "Quit did not ask \(question)", in: console)
        // The gallery's stand-in answers by closing the question and keeps
        // the app paused, as GameUITests has it for a game.
        tap(console.buttons[Words.quitApp], "Quit the app, in the question", in: console)
        expect(waitForGone(asked), "The question stayed once answered", in: console)
        expect(console.buttons[Words.resume].waitForExistence(timeout: 10), "\(appName) went once the question was answered", in: console)
        expectMainThreadAnswered(console)
    }
}
