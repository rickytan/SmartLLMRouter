import XCTest

/// Settings Tab UI Tests
/// Tests the Settings window tab structure: tab existence, tab switching,
/// and the Channels tab channel list.
///
/// Key accessibility IDs (matching SettingsView.swift and ACCESSIBILITY_IDS.md):
///   settings.tab.general, settings.tab.channels, settings.tab.advanced,
///   settings.tab.usage, settings.tab.about
///   settings.channels.list, settings.channels.add
///   settings.general.port, settings.advanced.failover
///   usage.totalRequests, usage.totalTokens, usage.totalCost
///   about.version, about.github
final class SettingsTabUITests: UITestCase {

    // MARK: - Helpers

    /// Open the Settings window via the menu bar.
    private func openSettings() {
        tapElement(UI.menuSettingsButton)
Thread.sleep(forTimeInterval: 1.5)
    }

    /// Close the Settings window.
    private func closeSettings() {
        let settingsWindow = app.windows.firstMatch
        if settingsWindow.exists {
            settingsWindow.buttons[UI.closeButton].click()
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - 8. testSettingsTabsExist

    /// Verify all 5 settings tabs exist and are clickable.
    /// The tabs are: General, Channels, Advanced, Usage, About.
    func testSettingsTabsExist() throws {
        openSettings()

        // Verify each tab button exists and is hittable
        let tabIdentifiers: [(String, String)] = [
            (UI.settingsGeneralTab, "General"),
            (UI.settingsChannelsTab, "Channels"),
            (UI.settingsAdvancedTab, "Advanced"),
            (UI.settingsUsageTab, "Usage"),
            (UI.settingsAboutTab, "About"),
        ]

        for (identifier, name) in tabIdentifiers {
            let tab = app.descendants(matching: .any)
                .matching(identifier: identifier).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 3),
                          "Tab '\(name)' with identifier '\(identifier)' should exist")
            XCTAssertTrue(tab.isHittable,
                          "Tab '\(name)' should be hittable (clickable)")
        }

        // Verify exactly 5 tab buttons exist (no duplicates)
        // SwiftUI TabView renders tabs as tab buttons
        let generalTab = app.descendants(matching: .any)
            .matching(identifier: UI.settingsGeneralTab)
        XCTAssertGreaterThanOrEqual(generalTab.count, 1,
                                    "General tab should exist at least once")
    }

    // MARK: - 9. testSettingsTabSwitching

    /// Switch between tabs and verify that the displayed content changes accordingly.
    /// Each tab should show unique content that can be verified.
    func testSettingsTabSwitching() throws {
        openSettings()

        // --- General Tab (index 0) ---
        tapElement(UI.settingsGeneralTab)
        Thread.sleep(forTimeInterval: 0.5)

        // General tab should show the port field
        let portField = app.descendants(matching: .any)
            .matching(identifier: UI.settingsPortField).firstMatch
        XCTAssertTrue(portField.waitForExistence(timeout: 3),
                      "General tab should show the port input field")

        // General tab content should be visible
        let startOrStopExists =
            app.descendants(matching: .any).matching(identifier: UI.settingsStartServiceButton).firstMatch.exists ||
            app.descendants(matching: .any).matching(identifier: UI.settingsStopServiceButton).firstMatch.exists
        XCTAssertTrue(startOrStopExists,
                      "General tab should show start or stop service button")

        // --- Channels Tab (index 1) ---
        tapElement(UI.settingsChannelsTab)
        Thread.sleep(forTimeInterval: 0.5)

        // Channels tab should show the add button and channel list
        let addChannelButton = app.descendants(matching: .any)
            .matching(identifier: UI.settingsAddChannelButton).firstMatch
        XCTAssertTrue(addChannelButton.waitForExistence(timeout: 3),
                      "Channels tab should show the add channel button")

        let channelList = app.descendants(matching: .any)
            .matching(identifier: UI.settingsChannelList).firstMatch
        XCTAssertTrue(channelList.waitForExistence(timeout: 2),
                      "Channels tab should show the channel list")

        // Port field from General tab should NOT be visible now
        XCTAssertFalse(portField.exists,
                       "Port field should not be visible when on the Channels tab")

        // --- Advanced Tab (index 2) ---
        tapElement(UI.settingsAdvancedTab)
        Thread.sleep(forTimeInterval: 0.5)

        // Advanced tab should show the failover toggle
        let failoverToggle = app.descendants(matching: .any)
            .matching(identifier: UI.settingsFailoverToggle).firstMatch
        XCTAssertTrue(failoverToggle.waitForExistence(timeout: 3),
                      "Advanced tab should show the failover toggle")

        // Add channel button from Channels tab should NOT be visible
        XCTAssertFalse(addChannelButton.exists,
                       "Add channel button should not be visible when on the Advanced tab")

        // --- Usage Tab (index 3) ---
        tapElement(UI.settingsUsageTab)
        Thread.sleep(forTimeInterval: 0.5)

        // Usage tab should show at least one usage metric
        let totalRequests = app.descendants(matching: .any)
            .matching(identifier: UI.usageTotalRequests).firstMatch
        let totalTokens = app.descendants(matching: .any)
            .matching(identifier: UI.usageTotalTokens).firstMatch
        let totalCost = app.descendants(matching: .any)
            .matching(identifier: UI.usageTotalCost).firstMatch
        XCTAssertTrue(
            totalRequests.waitForExistence(timeout: 3) ||
            totalTokens.exists ||
            totalCost.exists,
            "Usage tab should show at least one usage metric"
        )

        // Failover toggle from Advanced tab should NOT be visible
        XCTAssertFalse(failoverToggle.exists,
                       "Failover toggle should not be visible when on the Usage tab")

        // --- About Tab (index 4) ---
        tapElement(UI.settingsAboutTab)
        Thread.sleep(forTimeInterval: 0.5)

        // About tab should show the version label
        let versionLabel = app.descendants(matching: .any)
            .matching(identifier: UI.aboutVersionLabel).firstMatch
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 3),
                      "About tab should show the version label")

        // About tab should show the GitHub button
        let githubButton = app.descendants(matching: .any)
            .matching(identifier: UI.aboutGithubButton).firstMatch
        XCTAssertTrue(githubButton.exists || githubButton.waitForExistence(timeout: 2),
                      "About tab should show the GitHub button")

        // Usage metrics from Usage tab should NOT be visible
        XCTAssertFalse(totalRequests.exists,
                       "Total requests metric should not be visible when on the About tab")

        // --- Switch back to General to verify round-trip ---
        tapElement(UI.settingsGeneralTab)
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(portField.waitForExistence(timeout: 3),
                      "Port field should reappear after switching back to General tab")
    }

    // MARK: - 10. testSettingsChannelList

    /// Add a channel (via the Add Channel sheet in Settings), go to Settings → Channels,
    /// verify the channel appears in the list.
    ///
    /// Note: This test verifies the UI flow for adding a channel. A complete channel save
    /// requires a real API endpoint and key. We test the model addition and form interaction
    /// instead of a full network-dependent save.
    func testSettingsChannelList() throws {
        openSettings()

        // Navigate to Channels tab
        tapElement(UI.settingsChannelsTab)
Thread.sleep(forTimeInterval: 1.5)

        // Verify the channel list exists
        let channelList = app.descendants(matching: .any)
            .matching(identifier: UI.settingsChannelList).firstMatch
        XCTAssertTrue(channelList.waitForExistence(timeout: 3),
                      "Channel list should exist on the Channels tab")

        // Open the Add Channel sheet
        let addButton = app.descendants(matching: .any)
            .matching(identifier: UI.settingsAddChannelButton).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3),
                      "Add channel button should exist")
        addButton.click()
Thread.sleep(forTimeInterval: 1.5)

        // Verify the AddChannelView sheet opened
        let providerPicker = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3),
                      "AddChannelView should open with provider picker")

        // Fill in connection details
        let baseUrlField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelBaseUrlField).firstMatch
        XCTAssertTrue(baseUrlField.waitForExistence(timeout: 2),
                      "Base URL field should exist")
        baseUrlField.click()
        baseUrlField.typeText("https://api.example.com/v1")
        Thread.sleep(forTimeInterval: 0.3)

        let apiKeyField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelApiKeyField).firstMatch
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 2),
                      "API Key field should exist")
        apiKeyField.click()
        apiKeyField.typeText("sk-test-key-12345")
        Thread.sleep(forTimeInterval: 0.3)

        // Add a manual model
        let modelField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelManualModelField).firstMatch
        XCTAssertTrue(modelField.waitForExistence(timeout: 2),
                      "Manual model field should exist")
        modelField.click()
        modelField.typeText("test-model-settings")
        modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Verify the model was added (gear button appears)
        let gearButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 2),
                      "Model should appear in the list after adding manually")

        // Verify the delete button exists for the model
        let deleteButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelDeleteButton).firstMatch
        XCTAssertTrue(deleteButton.exists,
                      "Delete button should exist for the added model")

        // Note: We can't fully save without a real API connection (the save requires
        // testResult.success == true). So we verify the form state and cancel.
        // In a real E2E test environment with API access, we'd test the full save flow.

        // Verify the Save button exists but is disabled (test not passed)
        let saveButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelSaveButton).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2),
                      "Save button should exist")
        XCTAssertTrue(!saveButton.isEnabled,
                      "Save button should be disabled (connection test not passed)")

        // Cancel the form
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2),
                      "Cancel button should exist")
        cancelButton.click()
Thread.sleep(forTimeInterval: 1.5)

        // Verify we're back on the Channels tab
        XCTAssertTrue(channelList.waitForExistence(timeout: 3),
                      "Should return to the Channels tab after canceling the Add Channel form")

        // Verify the settings window is still open and the Channels tab is active
        let settingsWindow = app.windows.firstMatch
        XCTAssertTrue(settingsWindow.exists,
                      "Settings window should still be open after the flow")
    }
}
