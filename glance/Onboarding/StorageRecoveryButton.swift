import SwiftUI

/// Also reachable during setup, where the regular Password settings tab is gated.
struct StorageRecoveryButton: View {
    let controller: OnboardingController
    @State private var showRecovery = false

    var body: some View {
        Button(L10n.ui("Recover secure setup…")) { showRecovery = true }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showRecovery) {
                VStack(alignment: .leading, spacing: 16) {
                    Label(L10n.ui("Start a new secure setup"), systemImage: "lock.shield")
                        .font(.title2.bold())
                    Text(L10n.ui("Glance cannot access the key for the previous encrypted data. This can happen after reinstalling or changing the app's signing identity."))
                    Text(L10n.ui("Your previous encrypted password and face data will be kept untouched. They cannot be restored without their original key. A new, separate storage area will hold this setup's face samples and the password you enter."))
                    Text(L10n.ui("You will authenticate with Touch ID or your Mac password. Cancelling authentication leaves the current setup unchanged."))
                        .foregroundStyle(.secondary)
                    if let error = controller.storageRecoveryError {
                        Text(L10n.ui(error)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(L10n.ui("Cancel")) { showRecovery = false }
                            .disabled(controller.isRecoveringStorage)
                        Spacer()
                        Button(L10n.ui(controller.isRecoveringStorage ? "Authenticating…" : "Keep old data & continue")) {
                            Task {
                                await controller.recoverStorage()
                                if !controller.storageRecoveryRequired { showRecovery = false }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.isRecoveringStorage)
                    }
                }
                .padding(24)
                .frame(width: 430)
                .fixedSize(horizontal: false, vertical: true)
                .interactiveDismissDisabled(controller.isRecoveringStorage)
            }
    }
}
