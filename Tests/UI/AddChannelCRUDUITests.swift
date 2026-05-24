import XCTest

/// AddChannel CRUD UI Tests
/// Tests the AddChannelView modal form: validation, manual model entry,
/// model metadata editor, and cancel behavior.
///
/// These tests open the AddChannelView through the Settings → Channels tab flow.
///
/// Key accessibility IDs (matching AddChannelView.swift):
///   addChannel.providerPicker, addChannel.protocolPicker,
///   addChannel.baseUrlField, addChannel.apiKeyField,
///   addChannel.testConnectionButton, addChannel.fetchModelsButton,
///   addChannel.saveButton, addChannel.cancelButton,
///   addChannel.manualModelField, addChannel.modelRow.editButton,
///   addChannel.modelRow.deleteButton
///   modelEditor.saveButton, modelEditor.cancelButton,
///   modelEditor.contextLengthField
final class AddChannelCRUDUITests: UITestCase {

    // MARK: - Helpers

    /// Navigate to Settings → Channels tab.
    private func openSettingsChannelsTab() {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        tapElement(UI.settingsChannelsTab)
        sleep(1)
    }

    /// Open the AddChannelView sheet via the "+" button.
    private func openAddChannelSheet() {
        let addButton = app.descendants(matching: .any)
            .matching(identifier: UI.settingsAddChannelButton).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3),
                      "Settings channels add button should exist")
        addButton.click()
        sleep(1)
    }

    /// Add a manual model via the text field and Return key.
    private func addManualModel(named name: String) {
        let modelField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelManualModelField).firstMatch
        if modelField.waitForExistence(timeout: 3) {
            modelField.click()
            modelField.typeText(name)
            modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            sleep(0.5)
        }
    }

    // MARK: - 4. testAddChannelFormValidation

    /// Verify the Save (Add Channel) button is disabled when the form is empty or
    /// has no models. The form requires: name, baseURL, apiKey, successful test, and
    /// at least one model to be valid. On a fresh open all of these are empty/false.
    func testAddChannelFormValidation() throws {
        openSettingsChannelsTab()
        openAddChannelSheet()

        // Verify the Save button exists
        let saveButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelSaveButton).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3),
                      "Save button should exist in the AddChannel form")

        // The Save button should be disabled because:
        // - name is empty
        // - baseURL is empty
        // - apiKey is empty
        // - testResult is nil (not successful)
        // - models is empty
        XCTAssertTrue(saveButton.isDisabled || !saveButton.isEnabled,
                      "Save button should be disabled when form fields are empty and no models added")

        // Verify essential form fields are present but empty
        let baseUrlField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelBaseUrlField).firstMatch
        XCTAssertTrue(baseUrlField.waitForExistence(timeout: 2),
                      "Base URL field should exist")
        XCTAssertEqual(baseUrlField.value as? String ?? "", "",
                       "Base URL field should be empty on a fresh form")

        let apiKeyField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelApiKeyField).firstMatch
        XCTAssertTrue(apiKeyField.waitForExistence(timeout: 2),
                      "API Key field should exist")

        // Test connection button should also be disabled (requires apiKey + baseURL)
        let testButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelTestConnectionButton).firstMatch
        XCTAssertTrue(testButton.waitForExistence(timeout: 2),
                      "Test Connection button should exist")
        XCTAssertTrue(testButton.isDisabled || !testButton.isEnabled,
                      "Test Connection button should be disabled when apiKey and baseURL are empty")

        // Fetch Models button should be disabled (requires successful test)
        let fetchButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelFetchModelsButton).firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 2),
                      "Fetch Models button should exist")
        XCTAssertTrue(fetchButton.isDisabled || !fetchButton.isEnabled,
                      "Fetch Models button should be disabled without a successful connection test")

        // Cancel to clean up
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.click()
            sleep(0.5)
        }
    }

    // MARK: - 5. testAddChannelManualModel

    /// Add a model manually via the input field, verify it appears in the model list.
    func testAddChannelManualModel() throws {
        openSettingsChannelsTab()
        openAddChannelSheet()

        // Initially, the model list should be empty (no gear buttons)
        let initialGearButtons = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton)
        XCTAssertEqual(initialGearButtons.count, 0,
                       "Should have no models initially")

        // Type a model name into the manual model field and press Return
        let modelField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelManualModelField).firstMatch
        XCTAssertTrue(modelField.waitForExistence(timeout: 3),
                      "Manual model input field should exist")
        modelField.click()
        modelField.typeText("gpt-4-test-model")
        sleep(0.3)

        // Press Return to add the model
        modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        sleep(0.5)

        // Verify the model appeared — the gear button (edit) should now exist
        let gearButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3),
                      "Gear button (edit) should appear after adding a model manually")

        // Verify the delete button also exists for the new model
        let deleteButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelDeleteButton).firstMatch
        XCTAssertTrue(deleteButton.exists,
                      "Delete button should appear for the newly added model")

        // Add a second model to verify multiple models can be added
        modelField.click()
        modelField.typeText("gpt-3.5-turbo-test")
        modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
        sleep(0.5)

        let gearButtonsAfter = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton)
        XCTAssertEqual(gearButtonsAfter.count, 2,
                       "Should have 2 gear buttons after adding a second model")

        // Delete the first model
        deleteButton.click()
        sleep(0.5)

        let gearButtonsAfterDelete = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton)
        XCTAssertEqual(gearButtonsAfterDelete.count, 1,
                       "Should have 1 gear button after deleting the first model")

        // Cancel to clean up
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.click()
            sleep(0.5)
        }
    }

    // MARK: - 6. testAddChannelModelEditor

    /// Click the gear button on a model, verify the model metadata editor appears,
    /// edit the context length, and save.
    func testAddChannelModelEditor() throws {
        openSettingsChannelsTab()
        openAddChannelSheet()

        // Add a model first
        addManualModel(named: "editor-test-model")
        sleep(0.5)

        // Click the gear (edit) button on the model row
        let gearButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3),
                      "Gear button should exist after adding a model")
        gearButton.click()
        sleep(1)

        // Verify the ModelMetadataEditorView opened
        let editorSaveButton = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorSaveButton).firstMatch
        let editorCancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorCancelButton).firstMatch
        XCTAssertTrue(
            editorSaveButton.waitForExistence(timeout: 3) || editorCancelButton.waitForExistence(timeout: 3),
            "Model metadata editor should open with Save and Cancel buttons"
        )

        // Verify the context length field exists and is editable
        let contextField = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorContextLengthField).firstMatch
        XCTAssertTrue(contextField.waitForExistence(timeout: 3),
                      "Context length field should exist in the model editor")

        // Edit the context length
        contextField.click()
        contextField.typeKey("a", modifierFlags: .command)
        contextField.typeText("128000")
        sleep(0.3)

        XCTAssertEqual(contextField.value as? String, "128000",
                       "Context length field should show the new value after editing")

        // Verify input and output price fields exist
        let inputPriceField = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorInputPriceField).firstMatch
        XCTAssertTrue(inputPriceField.waitForExistence(timeout: 2),
                      "Input price field should exist in the model editor")

        let outputPriceField = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorOutputPriceField).firstMatch
        XCTAssertTrue(outputPriceField.waitForExistence(timeout: 2),
                      "Output price field should exist in the model editor")

        // Click Save to close the editor and apply changes
        XCTAssertTrue(editorSaveButton.waitForExistence(timeout: 2),
                      "Save button should exist in the model editor")
        editorSaveButton.click()
        sleep(1)

        // Verify the editor closed — the Cancel button inside the editor should no longer exist
        let editorCancelAfterSave = app.descendants(matching: .any)
            .matching(identifier: UI.modelEditorCancelButton).firstMatch
        XCTAssertFalse(editorCancelAfterSave.exists,
                       "Model editor should close after clicking Save")

        // Verify we're back on the AddChannelView (gear button should still exist)
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3),
                      "Should return to AddChannelView after saving model metadata")

        // Cancel to clean up
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.click()
            sleep(0.5)
        }
    }

    // MARK: - 7. testAddChannelCancel

    /// Open the add channel modal, tap Cancel, verify it closes without saving.
    func testAddChannelCancel() throws {
        openSettingsChannelsTab()

        // Record the initial channel count (from the list)
        let initialChannelList = app.descendants(matching: .any)
            .matching(identifier: UI.settingsChannelList).firstMatch
        let channelListExistsBefore = initialChannelList.exists

        // Open AddChannel sheet
        openAddChannelSheet()

        // Verify the AddChannelView sheet opened (provider picker should be visible)
        let providerPicker = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3),
                      "AddChannelView should open — provider picker should be visible")

        // Fill in some form fields (but don't save)
        let baseUrlField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelBaseUrlField).firstMatch
        if baseUrlField.waitForExistence(timeout: 2) {
            baseUrlField.click()
            baseUrlField.typeText("https://api.example.com/v1")
            sleep(0.3)
        }

        // Add a model manually
        addManualModel(named: "model-to-discard")
        sleep(0.5)

        // Verify the model was added (gear button exists)
        let gearButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 2),
                      "Model should have been added before canceling")

        // Click the Cancel button at the bottom of the form
        let cancelButton = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelCancelButton).firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2),
                      "Cancel button should exist at the bottom of the AddChannel form")
        cancelButton.click()
        sleep(1)

        // Verify the sheet closed (provider picker should no longer exist)
        XCTAssertFalse(providerPicker.exists,
                       "AddChannelView should close after clicking Cancel")

        // Verify no channel was added — channel list should be in the same state
        let channelListAfter = app.descendants(matching: .any)
            .matching(identifier: UI.settingsChannelList).firstMatch
        if channelListExistsBefore {
            XCTAssertTrue(channelListAfter.exists,
                          "Channel list should still exist in the same state as before")
        }

        // Re-open and verify the form is fresh (not retaining previous input)
        openAddChannelSheet()
        let freshBaseUrlField = app.descendants(matching: .any)
            .matching(identifier: UI.addChannelBaseUrlField).firstMatch
        if freshBaseUrlField.waitForExistence(timeout: 3) {
            let fieldValue = freshBaseUrlField.value as? String ?? ""
            XCTAssertTrue(fieldValue.isEmpty,
                          "Base URL should be empty on a fresh open after canceling")
        }

        // Close via ESC key instead of Cancel button
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        sleep(0.5)

        // Verify it closed
        XCTAssertFalse(providerPicker.exists,
                       "AddChannelView should close when ESC is pressed")
    }
}
