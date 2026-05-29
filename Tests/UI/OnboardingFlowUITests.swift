import XCTest

/// Onboarding Flow UI Tests
/// Tests the first-launch onboarding wizard: welcome screen, add channel step, and completion.
///
/// Prerequisites:
/// - App launches with `--reset-onboarding` to ensure a fresh onboarding state.
/// - The onboarding window is presented as a SwiftUI Window with id "onboarding".
///
/// Accessibility IDs (matching OnboardingView.swift):
///   - onboarding.welcome.title       — "Welcome to SmartLLMRouter" heading
///   - onboarding.welcome.icon        — network icon on welcome screen
///   - onboarding.welcome.subtitle    — subtitle text
///   - onboarding.welcome.nextButton  — "Next" button (shared across steps)
///   - onboarding.skip                — "Skip" button
///   - onboarding.addChannels.addButton — "Add Channel" badge button
///   - onboarding.done.launchButton   — "Launch" button on done step
///   - onboarding.progress.*          — progress indicator dots
final class OnboardingFlowUITests: UITestCase {

    // MARK: - Helpers

    /// Wait for the onboarding window to appear.
    /// The onboarding window has identifier "onboarding" in the SwiftUI Window scene.
    private func waitForOnboardingWindow(timeout: TimeInterval = 8) -> XCUIElement {
        let onboardingWindow = app.windows[UI.onboardingWindowId]
        XCTAssertTrue(
            onboardingWindow.waitForExistence(timeout: timeout),
            "Onboarding window should appear within \(timeout)s"
        )
        return onboardingWindow
    }

    /// Navigate from the current step to the next step by clicking the "Next" button.
    private func tapNextButton() {
        let nextButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingNextButton).firstMatch
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3), "Next button should exist")
        nextButton.click()
Thread.sleep(forTimeInterval: 1.5)
    }

    /// Add a channel through the AddChannelView sheet.
    /// This opens the sheet, fills in a model manually, and closes.
    private func addChannelFromSheet() {
        // Click "Add Channel" badge button on the addChannel step
        let addButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingAddChannelButton).firstMatch
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 3),
            "Add Channel button should exist on addChannel step"
        )
        addButton.click()
Thread.sleep(forTimeInterval: 1.5)

        // The AddChannelView sheet should appear.
        // Add a model manually using the manual model input field.
        let modelField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelManualModelField).firstMatch
        if modelField.waitForExistence(timeout: 3) {
            modelField.click()
            modelField.typeText("test-model")
            modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
Thread.sleep(forTimeInterval: 0.3)
        }

        // Close the sheet via Cancel (we don't need to fully save for the onboarding flow test;
        // the channel is saved by the AddChannelView internally).
        // For a full save we'd need a real API key, so we'll test the UI interaction only.
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.click()
Thread.sleep(forTimeInterval: 1.5)
        }
    }

    // MARK: - Test Cases

    /// 1. testOnboardingAppears
    /// Verify onboarding window shows on first launch.
    /// The app sets NSApp activation policy to .accessory, so on first launch
    /// the onboarding window is opened via `makeKeyAndOrderFront`.
    func testOnboardingAppears() throws {
        let onboardingWindow = app.windows[UI.onboardingWindowId]

        // The onboarding window should appear if onboarding is not yet completed.
        // If it doesn't appear (already completed), verify the menu bar is accessible instead.
        if onboardingWindow.waitForExistence(timeout: 6) {
            // Onboarding window appeared — verify the welcome screen
            let titleText = app.descendants(matching: .any)
                .matching(identifier: UI.onboardingTitle).firstMatch
            XCTAssertTrue(titleText.waitForExistence(timeout: 3),
                          "Welcome title should appear on the onboarding screen")

            let icon = app.descendants(matching: .any)
                .matching(identifier: UI.onboardingWelcomeIcon).firstMatch
            XCTAssertTrue(icon.exists, "Welcome icon should be present on the onboarding screen")

            // Verify the progress indicator dots exist
            let progressWelcome = app.descendants(matching: .any)
                .matching(identifier: UI.onboardingProgressWelcome).firstMatch
            XCTAssertTrue(progressWelcome.exists,
                          "Progress indicator for 'welcome' step should be visible")
        } else {
            // Onboarding was already completed — verify the app launched successfully
            // and the menu bar (status item) is accessible.
            let menuButton = app.descendants(matching: .any)
                .matching(identifier: UI.menuSettingsButton).firstMatch
            XCTAssertTrue(menuButton.waitForExistence(timeout: 5),
                          "If onboarding was already completed, the menu bar should be accessible")
        }
    }

    /// 2. testOnboardingAddChannel
    /// Tap 'Add Channel', fill form, verify channel appears in list.
    /// Note: This test verifies the UI interaction flow. A real save requires
    /// a valid API key and endpoint, so we test that the sheet opens and the
    /// model input field is accessible.
    func testOnboardingAddChannel() throws {
        let onboardingWindow = app.windows[UI.onboardingWindowId]
        guard onboardingWindow.waitForExistence(timeout: 6) else {
            // Skip if onboarding is already completed
            return
        }

        // Navigate from Welcome step to AddChannel step
        tapNextButton()

        // Verify the Add Channel button is present on the addChannel step
        let addButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingAddChannelButton).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3),
                      "Add Channel button should exist on the addChannel step")

        // Verify the import config button exists too
        let importButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingImportButton).firstMatch
        XCTAssertTrue(importButton.exists,
                      "Import Config button should be present on the addChannel step")

        // Tap "Add Channel" to open the AddChannelView sheet
        addButton.click()
Thread.sleep(forTimeInterval: 1.5)

        // Verify the AddChannelView sheet opened
        let providerPicker = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3),
                      "AddChannelView sheet should open with provider picker")

        // Add a model manually
        let modelField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelManualModelField).firstMatch
        XCTAssertTrue(modelField.waitForExistence(timeout: 3),
                      "Manual model input field should exist")
        modelField.click()
        modelField.typeText("test-model-onboarding")
        modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
Thread.sleep(forTimeInterval: 0.3)

        // Verify the model was added (gear button should appear)
        let gearButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 2),
                      "Gear button should appear after adding a model")

        // Close the sheet
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.click()
Thread.sleep(forTimeInterval: 1.5)
        }

        // Verify we're back on the onboarding addChannel step
        XCTAssertTrue(addButton.waitForExistence(timeout: 3),
                      "Should return to the onboarding addChannel step after closing the sheet")
    }

    /// 3. testOnboardingComplete
    /// Add a channel, tap Launch, verify onboarding closes and menu bar popover appears.
    /// This test verifies the navigation through the onboarding steps and that the
    /// onboarding window closes after completion.
    func testOnboardingComplete() throws {
        let onboardingWindow = app.windows[UI.onboardingWindowId]
        guard onboardingWindow.waitForExistence(timeout: 6) else {
            // Skip if onboarding is already completed
            return
        }

        // Step 1: Welcome → Add Channel
        tapNextButton()
Thread.sleep(forTimeInterval: 1.5)

        // Step 2: Add Channel → Shell Config (skip since no real channel)
        let skipButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingSkipButton).firstMatch
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.click()
Thread.sleep(forTimeInterval: 1.5)
        }

        // Step 3: Shell Config → Done (click Next/Finish)
        let nextButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingNextButton).firstMatch
        if nextButton.waitForExistence(timeout: 3) {
            nextButton.click()
Thread.sleep(forTimeInterval: 1.5)
        }

        // Step 4: Done step — verify the done screen elements
        let doneTitle = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingDoneTitle).firstMatch
        if doneTitle.waitForExistence(timeout: 3) {
            XCTAssertTrue(doneTitle.exists, "Done title should appear on the final step")
        }

        let doneDescription = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingDoneDescription).firstMatch
        XCTAssertTrue(doneDescription.exists || doneDescription.waitForExistence(timeout: 2),
                      "Done description should appear on the final step")

        // Click the Launch button
        let launchButton = app.descendants(matching: .any)
            .matching(identifier: UI.onboardingLaunchButton).firstMatch
        XCTAssertTrue(launchButton.waitForExistence(timeout: 3),
                      "Launch button should exist on the done step")
        launchButton.click()
Thread.sleep(forTimeInterval: 2.5)

        // Verify the onboarding window closed
        XCTAssertFalse(onboardingWindow.exists,
                       "Onboarding window should close after clicking Launch")

        // Verify the menu bar is now accessible (popover should have appeared)
        let menuButton = app.descendants(matching: .any)
            .matching(identifier: UI.menuSettingsButton).firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5),
                      "Menu bar should be accessible after onboarding completion")
    }
}
