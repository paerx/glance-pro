# Continuous enrollment and credential regression checks

Run from the repository root with Xcode's Swift compiler:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc glance/Onboarding/EnrollmentPose.swift \
  glance/Onboarding/EnrollmentCapturePolicy.swift \
  glance/Onboarding/EnrollmentSampleProcessor.swift glance/FaceEmbedder.swift \
  tools/enrollment_selftest.swift -o /tmp/glance-enrollment-selftest
/tmp/glance-enrollment-selftest

xcrun swiftc glance/SecureCredentialManager.swift tools/credential_selftest.swift \
  -o /tmp/glance-credential-selftest
/tmp/glance-credential-selftest
```

The capture test runs the real binning and background sample-selection code
against deterministic Vision/model doubles. It covers all directions, quality
ranking, partial retries, wrong-identity exclusion, five-point alignment,
automatic reference-frame failures, monotonic progress and cancellation.

The credential test runs the real session/crypto manager against in-memory
Keychain and vault doubles. It covers orphan detection, query failures, cancelled
authentication, invalid keys, concurrent session creation, non-destructive
recovery, encrypt/decrypt/reopen, and preserving keys when face deletion fails.
Neither test reads real credentials or face data, activates the camera or prompts
for authentication.

Manual device checks still required: direct slow circle → blurred Thinking + live supplemental capture
overlay → naming; pause/reposition with missing angles; cancel during processing;
retry a failed password save; unlock the session after relaunch; test display sleep,
system sleep and screensaver exit; switch languages without restarting; recover an orphaned store from setup or Settings using a
disposable test profile. Check actual latency and recognition quality with a
real camera under different lighting. Do not delete a real session key to test.

Additional regressions (no real Keychain calls, screen locking or camera access):

```sh
xcrun swiftc glance/KeychainManager.swift tools/keychain_backend_selftest.swift -o /tmp/glance-keychain-selftest
/tmp/glance-keychain-selftest
xcrun swiftc glance/WakeTriggerPolicy.swift tools/wake_policy_selftest.swift -o /tmp/glance-wake-selftest
/tmp/glance-wake-selftest
xcrun swiftc glance/L10n.swift tools/localization_selftest.swift -o /tmp/glance-localization-selftest
/tmp/glance-localization-selftest
```

The backend test shadows Security entry points with in-memory functions and checks
backend selection, legacy reads, cancellation and access failures. The wake test
covers coalescing and cancellation. The localization test covers both languages,
live selection changes, and every shader parameter/color label in the catalog.
These do not validate real user-presence prompts, code-signing access groups, or
hardware wake latency. Use a normally signed build for the device checks.
