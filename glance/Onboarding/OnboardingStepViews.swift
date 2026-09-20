//
//  OnboardingStepViews.swift
//  glance
//
//  The screens of the notch-hosted onboarding flow. Each fills whatever panel size
//  OnboardingController reports for its step — sizing itself is the notch window's job.
//

import SwiftUI
import AppKit

// MARK: - 1. Intro

struct IntroStepView: View {
    let controller: OnboardingController

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ui("Glance"))
                    .font(GlanceTheme.Font.title)
                    .foregroundStyle(GlanceTheme.textPrimary)
                Text(L10n.ui("Face Unlock for Mac"))
                    .font(GlanceTheme.Font.button)
                    .foregroundStyle(GlanceTheme.textSecondary)

                Spacer(minLength: 12)

                PillButton(title: "Next") {
                    controller.advance()
                }
            }
            .padding(.leading, 4)
            Spacer(minLength: 4)
            GlanceLogoView()
                .frame(width: 106, height: 106)
                .padding(.top, 4)
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
        .onAppear {
            controller.playIntroSweepIfNeeded()
        }
    }
}

private struct GlanceLogoView: View {
    var body: some View {
        // Video already bakes in its own white rounded-card background — no extra chrome needed.
        LoopingVideoView(resourceName: "logoanimation")
    }
}

// MARK: - 2. Permissions

struct PermissionsStepView: View {
    let controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.ui("Permissions"))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
                .padding(.leading, 4)

            // Spacer(minLength: 0)

            PermissionRow(
                title: "Accessibility",
                detail: "Allow Glance to unlock your Mac",
                granted: controller.accessibilityGranted
            ) { controller.grantAccessibility() }

            PermissionRow(
                title: "Camera",
                detail: "Allow Glance to recognize your face",
                granted: controller.cameraPermission == .granted
            ) { controller.grantCamera() }

            // Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: "Next", isEnabled: controller.bothPermissionsGranted) {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
    }
}

// MARK: - 3. Security notice

struct SecurityNoticeStepView: View {
    let controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(GlanceTheme.textPrimary)
                .padding(.top, 25)
                .padding(.leading, 4)

            Text(L10n.ui("Glance is not as secure as Apple's FaceID or TouchID."))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Text(L10n.ui("It uses your Mac's standard webcam and is designed for convenience, not high-security authentication."))
                .font(GlanceTheme.Font.passwordCaption)
                .foregroundStyle(GlanceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                if controller.isPostUpdateNotice {
                    // Declining isn't a real option here — see `declinePostUpdateNotice()`.
                    PillButton(title: "No thanks", style: .secondary) {
                        controller.declinePostUpdateNotice()
                    }
                } else {
                    PillButton(title: "Back", style: .secondary) {
                        controller.back()
                    }
                }
                PillButton(title: "I understand", isDefault: true) {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
    }
}

// MARK: - 4. Pre set-up

struct PreSetupStepView: View {
    let controller: OnboardingController

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.ui("Set up Face\nRecognition"))
                        .font(GlanceTheme.Font.title)
                        .foregroundStyle(GlanceTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.ui("Slowly move your head\nin a circle"))
                        .font(GlanceTheme.Font.button)
                        .foregroundStyle(GlanceTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                .padding(.leading, 4)
                Spacer(minLength: 0)
                UnlockGlyphView()
                    .frame(width: 120, height: 120)
            }
            Spacer(minLength: 4)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: "Next") {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
    }
}

private struct UnlockGlyphView: View {
    var body: some View {
        LoopingVideoView(resourceName: "idleanimation")
    }
}

// MARK: - 5. Select camera

struct SelectCameraStepView: View {
    let controller: OnboardingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.ui("Select camera"))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
                .padding(.leading, 4)
                .padding(.top, 14)

            Text(L10n.ui("Used for Face enrollment and for unlocking your Mac"))
                .font(GlanceTheme.Font.passwordCaption)
                .foregroundStyle(GlanceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 2)

            CameraSelectionPill(
                label: controller.cameraSelectionLabel,
                devices: controller.cameraDevices
            ) { id in
                controller.selectCamera(id: id)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: "Next") {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
        .onAppear {
            controller.refreshCameraDevices()
            controller.applyDisplayPinForCameraSelection()
        }
    }
}

// MARK: - 6-8. Guided enrollment (camera + tick ring + camera-complete)

struct EnrollStepView: View {
    let controller: OnboardingController
    @Environment(\.notchPanelStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if controller.storageRecoveryRequired {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield").font(.system(size: 38))
                        Text(L10n.ui("Keep your previous data and start a new secure setup."))
                            .multilineTextAlignment(.center)
                        StorageRecoveryButton(controller: controller)
                    }
                    .padding(24)
                    .frame(height: OnboardingMetrics.enrollCameraClusterDiameter)
                } else if controller.isPreparingSession {
                    ProgressView().frame(height: OnboardingMetrics.enrollCameraClusterDiameter)
                } else {
                    cameraCluster
                }
            }
                .padding(.top, cameraTopPadding)
            Spacer(minLength: 8)
            instructionLabel
                .padding(.horizontal, OnboardingMetrics.enrollInstructionHorizontalPadding)
                .padding(.bottom, OnboardingMetrics.enrollInstructionBottomPadding)
            if controller.enrollmentError != nil || controller.camera.errorMessage != nil {
                Button(L10n.ui("Try again")) { controller.retryEnrollment() }
                    .padding(.bottom, 16)
            }
        }
        .blur(radius: controller.isOrganizingSamples && !controller.enrollmentComplete ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if controller.isOrganizingSamples && !controller.enrollmentComplete {
                ZStack {
                    Color.white.opacity(0.08)
                    Color.black.opacity(0.25)
                    VStack(spacing: 12) {
                        ShaderOrbView(configuration: GlanceSettings.shared.shaderOrbConfiguration, state: .thinking)
                            .frame(width: 136, height: 136)
                        Text(L10n.ui("Organizing samples"))
                            .font(.system(size: 17, weight: .semibold))
                        Text(L10n.ui(controller.refinementHint ?? "Keep your face visible — refining samples locally"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ProgressView(value: controller.processingProgress)
                            .frame(width: 180).tint(GlanceTheme.accent)
                    }
                    .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.isOrganizingSamples)
        .overlay(alignment: .topTrailing) {
            if showsCloseButton {
                EnrollmentCloseButton {
                    controller.back()
                }
                .padding(OnboardingMetrics.enrollCloseButtonEdgePadding)
            }
        }
        .background(GlanceTheme.panel)
    }

    private var showsCloseButton: Bool {
        !controller.enrollmentComplete && !controller.showCheckmark
    }

    private var cameraTopPadding: CGFloat {
        style == .pill
            ? OnboardingMetrics.enrollCameraTopPaddingPill
            : OnboardingMetrics.enrollCameraTopPaddingNotch
    }

    private var cameraCluster: some View {
        ZStack {
            EnrollmentRingView(controller: controller)

            CameraPreviewView(session: controller.camera.session, faces: [])
                .frame(
                    width: OnboardingMetrics.cameraCircleDiameter,
                    height: OnboardingMetrics.cameraCircleDiameter
                )
                .clipShape(Circle())
                .opacity(controller.cameraPreviewVisible && !controller.isOrganizingSamples ? 1 : 0)
                .animation(
                    .easeInOut(duration: OnboardingMetrics.previewFadeOut),
                    value: controller.cameraPreviewVisible
                )
                .overlay {
                    if controller.isTooFar && controller.cameraPreviewVisible && !controller.showCheckmark {
                        EnrollmentTooFarChevron()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: controller.isTooFar)

            if controller.isOrganizingSamples, !controller.enrollmentComplete, let image = controller.enrollmentBackdrop {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: OnboardingMetrics.cameraCircleDiameter, height: OnboardingMetrics.cameraCircleDiameter)
                    .clipShape(Circle())
            }

            if controller.showCheckmark {
                AnimatedCheckmark(color: GlanceTheme.accent, lineWidth: 8)
                    .frame(width: 70, height: 59)
                    .transition(.opacity)
                    .padding(.top, 4)
            }
        }
        .frame(
            width: OnboardingMetrics.enrollCameraClusterDiameter,
            height: OnboardingMetrics.enrollCameraClusterDiameter
        )
    }

    private var instructionLabel: some View {
        Text(L10n.ui(controller.enrollmentInstruction))
            .font(GlanceTheme.Font.instruction)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .id(controller.enrollmentInstruction)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: controller.enrollmentInstruction)
            .opacity(controller.guideVisible ? 1 : 0)
            .animation(
                .easeInOut(
                    duration: controller.guideVisible
                        ? OnboardingMetrics.enrollInstructionFadeIn
                        : OnboardingMetrics.enrollInstructionFadeOut
                ),
                value: controller.guideVisible
            )
    }
}

private struct EnrollmentCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.8))
                .frame(
                    width: OnboardingMetrics.enrollCloseButtonSize,
                    height: OnboardingMetrics.enrollCloseButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Close")
    }
}

private struct EnrollmentTooFarChevron: View {
    var body: some View {
        Image(systemName: "chevron.up.2")
            .font(.system(size: OnboardingMetrics.enrollTooFarChevronSize, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
            .symbolEffect(.bounce.up.byLayer, options: .repeating)
            .accessibilityHidden(true)
    }
}

// MARK: - 9. Name

/// Asks who was just captured — for a recapture, pre-filled with the existing name so
/// this doubles as rename.
struct NameStepView: View {
    @Bindable var controller: OnboardingController

    private var trimmedName: String {
        controller.pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.ui("Name this face"))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
                .padding(.leading, 4)

            Text(L10n.ui("Used to tell enrolled faces apart when more than one person is set up on this Mac."))
                .font(GlanceTheme.Font.passwordCaption)
                .foregroundStyle(GlanceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 2)

            PillTextField(placeholder: "Enter a name...", text: $controller.pendingName, autofocus: true) {
                controller.confirmName()
            }

            if let error = controller.nameError {
                Text(L10n.ui(error))
                    .font(GlanceTheme.Font.rowDetail)
                    .foregroundStyle(GlanceTheme.statusDenied)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: controller.nameStepPrimaryTitle, isEnabled: !trimmedName.isEmpty, isDefault: true) {
                    controller.confirmName()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
    }
}

// MARK: - 10. Password

struct PasswordStepView: View {
    let controller: OnboardingController

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.ui("Enter your password"))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
                .padding(.leading, 4)

            Text(L10n.ui("Your password is required to unlock your Mac. It is encrypted and securely stored on your device. Glance works entirely offline, so your password never leaves your Mac."))
                .font(GlanceTheme.Font.passwordCaption)
                .foregroundStyle(GlanceTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 2)

            PillSecureField(placeholder: "Enter password...", text: $password, autofocus: true) {
                guard !password.isEmpty, !controller.isSavingPassword else { return }
                Task { _ = await controller.finish(password: password) }
            }

            if let error = controller.passwordError {
                Text(L10n.ui(error))
                    .font(GlanceTheme.Font.rowDetail)
                    .foregroundStyle(GlanceTheme.statusDenied)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.storageRecoveryRequired {
                StorageRecoveryButton(controller: controller)
            }

            // Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary, isEnabled: !controller.isSavingPassword) {
                    controller.back()
                }
                PillButton(
                    title: controller.isSavingPassword ? "Saving…" : "Confirm",
                    isEnabled: !password.isEmpty && !controller.isSavingPassword && !controller.storageRecoveryRequired,
                    isDefault: true
                ) {
                    Task { _ = await controller.finish(password: password) }
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlanceTheme.panel)
    }
}

// MARK: - 11. Complete

struct CompleteStepView: View {
    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.ui("You're all set"))
                .font(GlanceTheme.Font.title)
                .foregroundStyle(GlanceTheme.textPrimary)
            Spacer(minLength: 4)
            AnimatedCheckmark(color: .white, lineWidth: 5)
                .frame(width: 20, height: 15)
        }
        .onboardingContentHorizontalPadding()
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(GlanceTheme.panel)
    }
}
