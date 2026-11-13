//
//  CartoucheIPhoneAppsView.swift
//  Cartouche
//
//  Apps on this iPhone, on the System page (decision 88): the apps
//  Cartouche installed as apps of their own through its built-in SideStore,
//  each with its App ID, when its signature expires, Open, Renew and
//  Uninstall, and Install an IPA on this iPhone, from Files; under them,
//  the App IDs Apple keeps for the Apple ID, as SideStore's App IDs page
//  lists them, fetched on demand. The actions and the lists are
//  CartoucheIPhoneApps'. One action at a time, its progress in its row as
//  Renew now shows its own; a failure under the row, with its report.
//

import SwiftUI
import UniformTypeIdentifiers

/// The System page's row: how many apps, and when the first expires. With
/// a p12 and its profile, or without the built-in SideStore's bridge, why
/// there can be none.
@available(iOS 17.0, *)
struct CartoucheIPhoneAppsSection: View {
    @ObservedObject private var model = CartoucheIPhoneApps.shared

    var body: some View {
        Section {
            if CartoucheIPhoneApps.isAvailable {
                NavigationLink {
                    CartoucheIPhoneAppsView()
                } label: {
                    LabeledContent {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(CartoucheText.appsTitle, systemImage: "square.stack.3d.up")
                    }
                }
            }
        } footer: {
            if let reason = CartoucheIPhoneApps.unavailableReason {
                Text(reason)
            }
        }
        .onAppear { model.reload() }
    }

    private var summary: String {
        let apps = model.apps
        guard !apps.isEmpty else { return CartoucheText.appsNone }
        let count = apps.count == 1 ? CartoucheText.appsCountOne : CartoucheText.appsCount(apps.count)
        guard let soonest = apps.compactMap(\.daysLeft).min() else { return count }
        let when = soonest < 0 ? CartoucheText.appsOneExpired : soonest == 0 ? CartoucheText.appsSoonestToday
            : CartoucheText.appsSoonest(soonest)
        return count + ", " + when
    }
}

@available(iOS 17.0, *)
struct CartoucheIPhoneAppsView: View {
    @ObservedObject private var model = CartoucheIPhoneApps.shared
    @State private var choosingIPA = false
    @State private var uninstalling: CartoucheIPhoneApp?
    @State private var openFailed: CartoucheIPhoneApp?

    var body: some View {
        List {
            Section {
                if let work = model.work, case .installing = work.kind {
                    progressRow(CartoucheText.appsInstalling(work.name), work.progress)
                } else {
                    Button(CartoucheText.appsInstall, systemImage: "square.and.arrow.down") { choosingIPA = true }
                        .disabled(model.work != nil)
                }
                if let failure = model.failures[CartoucheIPhoneApps.installFailure] {
                    failureRows(failure)
                }
            } footer: {
                Text(CartoucheText.appsFooter)
            }
            if model.apps.isEmpty {
                Section {
                    Text(CartoucheText.appsNone)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.apps) { app in
                Section {
                    appRows(app)
                } header: {
                    Text(app.name)
                }
            }
            appIDsSection
        }
        .scrollContentBackground(.hidden)
        .cartoucheStageBackground()
        .navigationTitle(CartoucheText.appsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .fileImporter(isPresented: $choosingIPA, allowedContentTypes: Self.ipaTypes) { result in
            guard case .success(let url) = result else { return }
            Task { await model.install(ipa: url) }
        }
        .alert(uninstalling.map { CartoucheText.appsUninstallQuestion($0.name) } ?? "", isPresented: uninstallAsked,
               presenting: uninstalling) { app in
            Button(CartoucheText.appsUninstallConfirm, role: .destructive) { Task { await model.remove(app) } }
            Button(CartoucheText.cancel, role: .cancel) {}
        }
        .alert(openFailed.map { CartoucheText.appsOpenFailed($0.name) } ?? "", isPresented: openFailedShown,
               presenting: openFailed) { _ in
            Button(CartoucheText.done) {}
        }
    }

    private static var ipaTypes: [UTType] { [UTType(filenameExtension: "ipa") ?? .data, .data] }

    private var uninstallAsked: Binding<Bool> {
        Binding(get: { uninstalling != nil }, set: { if !$0 { uninstalling = nil } })
    }

    private var openFailedShown: Binding<Bool> {
        Binding(get: { openFailed != nil }, set: { if !$0 { openFailed = nil } })
    }

    @ViewBuilder
    private func appRows(_ app: CartoucheIPhoneApp) -> some View {
        // The identifier SideStore registered the app under with Apple, as
        // its App IDs screen lists it: the bundle identifier with the team's
        // appended for a free Apple ID.
        LabeledContent(CartoucheText.appsAppID) {
            Text(app.resignedBundleIdentifier)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        if let expirationDate = app.expirationDate, let daysLeft = app.daysLeft {
            LabeledContent(CartoucheText.expires, value: expirationDate.formatted(date: .abbreviated, time: .shortened))
            LabeledContent(CartoucheText.daysLeft) {
                Text(daysLeft < 0 ? CartoucheText.expired : String(daysLeft))
                    .foregroundStyle(daysLeft < 0 ? Color.red : daysLeft <= 2 ? Color.orange : Color.secondary)
                    .fontWeight(daysLeft <= 2 ? .semibold : .regular)
            }
        } else {
            Text(CartoucheText.profileUnknown)
                .foregroundStyle(.secondary)
        }
        if let refreshedDate = app.refreshedDate {
            LabeledContent(CartoucheText.renewed, value: refreshedDate.formatted(date: .abbreviated, time: .shortened))
        }
        if let work = model.work, work.bundleIdentifier == app.bundleIdentifier {
            switch work.kind {
            case .renewing: progressRow(CartoucheText.appsRenewing(app.name), work.progress)
            default: progressRow(CartoucheText.appsRemoving(app.name), work.progress)
            }
        } else {
            Button(CartoucheText.open, systemImage: "arrow.up.forward.app") {
                Task { if await !model.open(app) { openFailed = app } }
            }
            .disabled(model.work != nil)
            Button(CartoucheText.appsRenew, systemImage: "arrow.triangle.2.circlepath") {
                Task { await model.renew(app) }
            }
            .disabled(model.work != nil)
            Button(role: .destructive) { uninstalling = app } label: {
                Label(CartoucheText.uninstall, systemImage: "trash")
                    .foregroundStyle(CartoucheTheme.danger)
            }
            .disabled(model.work != nil)
        }
        if let failure = model.failures[app.bundleIdentifier] {
            failureRows(failure)
        }
    }

    // MARK: App IDs

    /// The App IDs Apple keeps for the Apple ID, as SideStore's App IDs page
    /// lists them: name, bundle identifier, Apple's identifier and expiry,
    /// the one that expires first first. Fetched on demand; the last fetch
    /// stays.
    private var appIDsSection: some View {
        Section {
            if let work = model.work, case .fetchingAppIDs = work.kind {
                progressRow(CartoucheText.appIDsFetching, work.progress)
            } else {
                Button(model.appIDs == nil ? CartoucheText.appIDsFetch : CartoucheText.appIDsRefresh, systemImage: "arrow.clockwise") {
                    Task { await model.fetchAppIDs() }
                }
                .disabled(model.work != nil)
            }
            if let failure = model.failures[CartoucheIPhoneApps.appIDsFailure] {
                failureRows(failure)
            }
            if let listing = model.appIDs {
                if listing.appIDs.isEmpty {
                    Text(CartoucheText.appIDsNone)
                        .foregroundStyle(.secondary)
                }
                ForEach(listing.appIDs) { appID in
                    appIDRow(appID)
                }
            }
        } header: {
            Text(CartoucheText.appIDsTitle)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let listing = model.appIDs {
                    let fetched = listing.date.formatted(date: .abbreviated, time: .shortened)
                    Text(listing.appIDs.count == 1 ? CartoucheText.appIDsFetchedOne(fetched)
                         : CartoucheText.appIDsFetched(listing.appIDs.count, fetched))
                }
                Text(CartoucheText.appIDsFooter)
            }
        }
    }

    private func appIDRow(_ appID: CartoucheAppID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appID.name.isEmpty ? appID.bundleIdentifier : appID.name)
            Text(appID.bundleIdentifier)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Text(CartoucheText.appIDsID(appID.identifier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let expirationDate = appID.expirationDate {
                    let expired = expirationDate < .now
                    let when = expirationDate.formatted(date: .abbreviated, time: .omitted)
                    Text(expired ? CartoucheText.appIDsExpired(when) : CartoucheText.appIDsExpires(when))
                        .font(.caption)
                        .foregroundStyle(expired ? Color.red : Color.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func progressRow(_ step: String, _ progress: Progress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(step, systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            // SideStore reports its progress from another thread: read it
            // twice a second instead of observing it, as Renew now does.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                ProgressView(value: progress.fractionCompleted)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func failureRows(_ report: CartoucheReport) -> some View {
        Label(report.message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        CartoucheReportButton(report: report)
            .font(.footnote)
    }
}
