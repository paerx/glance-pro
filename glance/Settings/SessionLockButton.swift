//
//  SessionLockButton.swift
//  glance
//
//  The header's trailing pill: shows whether the Settings session is
//  unlocked, and doubles as its on/off switch — unlocks while locked, locks
//  while unlocked.
//

import SwiftUI

struct SessionLockButton: View {
    @Bindable var pocController: POCController

    @State private var isUnlocking = false
    @State private var showsError = false

    var body: some View {
        Button(action: toggleSession) {
            HStack(spacing: 7) {
                Image(systemName: pocController.isSessionUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    // `.replace` animates the padlock shackle popping open
                    // where supported; SwiftUI falls back to a crossfade.
                    .contentTransition(.symbolEffect(.replace))

                Text(L10n.ui(label))
                    .font(SettingsMetrics.headerButtonFont)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(SettingsMetrics.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: SettingsMetrics.headerButtonHeight)
            .background(Capsule().fill(SettingsMetrics.rowColor))
            .overlay(
                Capsule()
                    .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            )
            .contentShape(Capsule())
        }
        .alert(L10n.ui("Session locked"), isPresented: $showsError) {
            if pocController.requiresStorageRecovery {
                Button(L10n.ui("Recover secure setup…")) { OnboardingController.startEnrollmentOnly() }
            }
            Button(L10n.ui("Cancel"), role: .cancel) { }
        } message: { Text(L10n.ui(pocController.sessionError ?? "Session locked")) }
        .buttonStyle(.plain)
        // Only disabled mid-authentication — a tap then would double up the
        // Touch ID prompt or race the unresolved lock.
        .disabled(isUnlocking)
        .animation(SettingsMetrics.stateTransitionAnimation, value: pocController.isSessionUnlocked)
        .animation(SettingsMetrics.stateTransitionAnimation, value: isUnlocking)
        .onAppear { pocController.refreshCredentialStatus() }
        // Session changes are observed by POCController. Also refresh password
        // existence when setup closes, since saving it does not change the key.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
    }

    private var label: String {
        if pocController.isSessionUnlocked { return "Session unlocked" }
        return isUnlocking ? "Authenticating…" : "Session locked"
    }

    private func toggleSession() {
        if pocController.isSessionUnlocked {
            pocController.lockSession()
            return
        }
        isUnlocking = true
        Task {
            await pocController.unlockSession()
            isUnlocking = false
            showsError = pocController.sessionError != nil
        }
    }
}
