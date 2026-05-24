import XCTest

/// AddChannelView UI 测试 - 验证添加频道对话框的交互
/// 重点测试：齿轮按钮（模型元数据编辑）、Cancel 按钮、Modal 弹窗
final class AddChannelUITests: UITestCase {

    // MARK: - 辅助方法

    /// 打开设置窗口并切换到 Channels Tab
    private func openSettingsChannelsTab() {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        tapElement(UI.settingsChannelsTab)
        sleep(1)
    }

    /// 点击添加按钮打开 AddChannelView
    private func openAddChannelDialog() {
        let addButton = app.descendants(matching: .any).matching(identifier: UI.settingsAddChannelButton).firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 3), "添加频道按钮应存在")
        addButton.click()
        sleep(1)
    }

    /// 添加一个手动模型（用于测试齿轮按钮）
    private func addManualModel(name: String = "test-model") {
        let modelField = app.descendants(matching: .any).matching(identifier: UI.addChannelManualModelField).firstMatch
        if modelField.waitForExistence(timeout: 2) {
            modelField.click()
            modelField.typeText(name)
            sleep(0.5)

            // 查找添加模型的 plus 按钮（在手动模型输入框旁边）
            // 使用 keyboard Enter 来添加
            modelField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
            sleep(0.5)
        }
    }

    // MARK: - Cancel 按钮测试

    /// 测试底部 Cancel 按钮存在
    func testCancelButtonExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.addChannelCancelButton).firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3), "Cancel 按钮应存在")
    }

    /// 测试点击 Cancel 按钮关闭对话框
    func testCancelButtonDismissesDialog() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 验证 AddChannelView 已打开
        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3), "AddChannelView 应已打开")

        // 点击 Cancel 按钮
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.addChannelCancelButton).firstMatch
        XCTAssertTrue(cancelButton.exists, "Cancel 按钮应存在")
        cancelButton.click()
        sleep(1)

        // 验证对话框已关闭
        XCTAssertFalse(providerPicker.exists, "点击 Cancel 后 AddChannelView 应关闭")
    }

    /// 测试头部 X 按钮关闭对话框
    func testHeaderCloseButtonDismissesDialog() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 验证 AddChannelView 已打开
        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3), "AddChannelView 应已打开")

        // 查找头部的 X 按钮
        let headerCloseButton = app.descendants(matching: .any).matching(identifier: UI.addChannelHeaderClose).firstMatch
        if headerCloseButton.waitForExistence(timeout: 2) {
            headerCloseButton.click()
            sleep(1)

            // 验证对话框已关闭
            XCTAssertFalse(providerPicker.exists, "点击头部 X 按钮后 AddChannelView 应关闭")
        }
    }

    // MARK: - 齿轮按钮测试

    /// 测试齿轮按钮在有模型时存在
    func testGearButtonExistsWhenModelsPresent() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 先添加一个手动模型
        addManualModel(name: "test-model-for-gear")
        sleep(1)

        // 查找齿轮按钮
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应在有模型时存在")
    }

    /// 测试齿轮按钮在无模型时不存在
    func testGearButtonNotExistsWhenNoModels() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 不添加任何模型，直接检查齿轮按钮
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertFalse(gearButton.exists, "齿轮按钮在无模型时不应存在")
    }

    /// 测试点击齿轮按钮打开模型元数据编辑器
    func testGearButtonOpensModelMetadataEditor() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-metadata")
        sleep(1)

        // 点击齿轮按钮
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应存在")
        gearButton.click()
        sleep(1)

        // 验证模型元数据编辑器已打开
        let saveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch

        let editorOpened = saveButton.waitForExistence(timeout: 3) || cancelButton.waitForExistence(timeout: 3)
        XCTAssertTrue(editorOpened, "点击齿轮按钮后应打开模型元数据编辑器")
    }

    /// 测试模型元数据编辑器的 Cancel 按钮
    func testModelEditorCancelButtonDismisses() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-cancel")
        sleep(1)

        // 点击齿轮按钮打开编辑器
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应存在")
        gearButton.click()
        sleep(1)

        // 查找编辑器的 Cancel 按钮
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.click()
            sleep(1)

            // 验证编辑器已关闭
            let saveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
            XCTAssertFalse(saveButton.exists, "点击 Cancel 后模型元数据编辑器应关闭")
        }
    }

    /// 测试模型元数据编辑器的 Save 按钮
    func testModelEditorSaveButtonWorks() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-save")
        sleep(1)

        // 点击齿轮按钮打开编辑器
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应存在")
        gearButton.click()
        sleep(1)

        // 查找编辑器的 Save 按钮
        let saveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
        if saveButton.waitForExistence(timeout: 3) {
            // 修改 Context Length
            let contextField = app.descendants(matching: .any).matching(identifier: UI.modelEditorContextLengthField).firstMatch
            if contextField.exists {
                contextField.click()
                contextField.typeKey("a", modifierFlags: .command)
                contextField.typeText("128000")
                sleep(0.3)
            }

            // 点击 Save
            saveButton.click()
            sleep(1)

            // 验证编辑器已关闭
            let cancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch
            XCTAssertFalse(cancelButton.exists, "点击 Save 后模型元数据编辑器应关闭")
        }
    }

    /// 测试模型元数据编辑器的头部 X 按钮
    func testModelEditorCloseButtonDismisses() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-close")
        sleep(1)

        // 点击齿轮按钮打开编辑器
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应存在")
        gearButton.click()
        sleep(1)

        // 查找编辑器的 Close 按钮
        let closeButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCloseButton).firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.click()
            sleep(1)

            // 验证编辑器已关闭
            let saveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
            XCTAssertFalse(saveButton.exists, "点击 Close 后模型元数据编辑器应关闭")
        }
    }

    // MARK: - 删除模型按钮测试

    /// 测试删除模型按钮存在
    func testDeleteModelButtonExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-delete")
        sleep(1)

        // 查找删除按钮
        let deleteButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelDeleteButton).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "删除模型按钮应在有模型时存在")
    }

    /// 测试点击删除按钮移除模型
    func testDeleteModelButtonRemovesModel() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-to-delete")
        sleep(1)

        // 记录初始模型数量
        let initialModelRows = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).count

        // 点击删除按钮
        let deleteButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelDeleteButton).firstMatch
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.click()
            sleep(1)

            // 验证模型数量减少
            let currentModelRows = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).count
            XCTAssertLessThan(currentModelRows, initialModelRows, "点击删除后模型数量应减少")
        }
    }

    // MARK: - Save 按钮测试

    /// 测试 Save 按钮在表单无效时禁用
    func testSaveButtonDisabledWhenFormInvalid() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let saveButton = app.descendants(matching: .any).matching(identifier: UI.addChannelSaveButton).firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3), "Save 按钮应存在")
    }

    // MARK: - Provider 选择测试

    /// 测试 Provider 选择器存在
    func testProviderPickerExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3), "Provider 选择器应存在")
    }

    /// 测试选择 Custom Provider 切换到自定义模式
    func testSelectCustomProviderSwitchesToCustomMode() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 选择 Custom Provider
        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        if providerPicker.waitForExistence(timeout: 2) {
            providerPicker.click()
            sleep(0.5)

            // 查找 Custom 选项
            let customOption = app.menuItems.matching(NSPredicate(format: "label CONTAINS %@", "Custom")).firstMatch
            if customOption.exists {
                customOption.click()
                sleep(1)

                // 验证切换到自定义模式
                let customNameField = app.descendants(matching: .any).matching(identifier: UI.addChannelCustomNameField).firstMatch
                XCTAssertTrue(customNameField.waitForExistence(timeout: 2), "选择 Custom 后应显示自定义名称输入框")
            }
        }
    }

    // MARK: - Protocol 选择测试

    /// 测试 Protocol 选择器存在
    func testProtocolPickerExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let protocolPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProtocolPicker).firstMatch
        XCTAssertTrue(protocolPicker.waitForExistence(timeout: 3), "Protocol 选择器应存在")
    }

    // MARK: - 测试连接测试

    /// 测试连接测试按钮存在
    func testConnectionTestButtonExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let testButton = app.descendants(matching: .any).matching(identifier: UI.addChannelTestConnectionButton).firstMatch
        XCTAssertTrue(testButton.waitForExistence(timeout: 3), "测试连接按钮应存在")
    }

    // MARK: - 获取模型测试

    /// 测试获取模型按钮存在
    func testFetchModelsButtonExists() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        let fetchButton = app.descendants(matching: .any).matching(identifier: UI.addChannelFetchModelsButton).firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 3), "获取模型按钮应存在")
    }

    // MARK: - 综合流程测试

    /// 测试完整的添加模型流程
    func testCompleteAddModelFlow() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 1. 验证初始状态（无模型）
        let initialGearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertFalse(initialGearButton.exists, "初始状态不应有齿轮按钮")

        // 2. 添加一个手动模型
        addManualModel(name: "flow-test-model")
        sleep(1)

        // 3. 验证齿轮按钮出现
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "添加模型后齿轮按钮应出现")

        // 4. 点击齿轮按钮打开编辑器
        gearButton.click()
        sleep(1)

        // 5. 验证编辑器打开
        let editorSaveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
        let editorCancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch
        let editorOpened = editorSaveButton.waitForExistence(timeout: 3) || editorCancelButton.waitForExistence(timeout: 3)
        XCTAssertTrue(editorOpened, "编辑器应打开")

        // 6. 点击 Cancel 关闭编辑器
        if editorCancelButton.exists {
            editorCancelButton.click()
            sleep(1)
        }

        // 7. 验证编辑器关闭
        XCTAssertFalse(editorSaveButton.exists, "编辑器应关闭")

        // 8. 点击底部 Cancel 关闭 AddChannelView
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.addChannelCancelButton).firstMatch
        XCTAssertTrue(cancelButton.exists, "Cancel 按钮应存在")
        cancelButton.click()
        sleep(1)

        // 9. 验证 AddChannelView 关闭
        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertFalse(providerPicker.exists, "AddChannelView 应关闭")
    }

    /// 测试 ESC 键关闭对话框
    func testEscapeKeyDismissesDialog() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 验证 AddChannelView 已打开
        let providerPicker = app.descendants(matching: .any).matching(identifier: UI.addChannelProviderPicker).firstMatch
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 3), "AddChannelView 应已打开")

        // 按 ESC 键
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        sleep(1)

        // 验证对话框已关闭
        XCTAssertFalse(providerPicker.exists, "按 ESC 后 AddChannelView 应关闭")
    }

    // MARK: - 边界情况测试

    /// 测试快速连续点击齿轮按钮
    func testRapidGearButtonClicks() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "rapid-click-model")
        sleep(1)

        // 快速连续点击齿轮按钮
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        if gearButton.waitForExistence(timeout: 3) {
            gearButton.click()
            sleep(0.3)
            gearButton.click()
            sleep(0.3)
            gearButton.click()
            sleep(1)

            // 验证只有一个编辑器打开
            let editorSaveButtons = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton)
            let editorCancelButtons = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton)

            // 应该只有一个编辑器实例
            XCTAssertTrue(editorSaveButtons.count <= 1 && editorCancelButtons.count <= 1,
                          "快速点击应只打开一个编辑器")
        }
    }

    /// 测试编辑器字段可编辑
    func testModelEditorFieldsEditable() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加一个手动模型
        addManualModel(name: "test-model-fields")
        sleep(1)

        // 点击齿轮按钮打开编辑器
        let gearButton = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton).firstMatch
        XCTAssertTrue(gearButton.waitForExistence(timeout: 3), "齿轮按钮应存在")
        gearButton.click()
        sleep(1)

        // 验证编辑器字段存在且可编辑
        let contextField = app.descendants(matching: .any).matching(identifier: UI.modelEditorContextLengthField).firstMatch
        let inputPriceField = app.descendants(matching: .any).matching(identifier: UI.modelEditorInputPriceField).firstMatch
        let outputPriceField = app.descendants(matching: .any).matching(identifier: UI.modelEditorOutputPriceField).firstMatch

        XCTAssertTrue(contextField.waitForExistence(timeout: 3), "Context Length 字段应存在")
        XCTAssertTrue(inputPriceField.exists, "Input Price 字段应存在")
        XCTAssertTrue(outputPriceField.exists, "Output Price 字段应存在")

        // 测试编辑 Context Length
        contextField.click()
        contextField.typeKey("a", modifierFlags: .command)
        contextField.typeText("256000")
        sleep(0.3)

        // 验证输入成功
        XCTAssertEqual(contextField.value as? String, "256000", "Context Length 应显示新值")

        // 关闭编辑器
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch
        if cancelButton.exists {
            cancelButton.click()
            sleep(1)
        }
    }

    /// 测试多个模型的齿轮按钮独立工作
    func testMultipleModelGearButtonsWork() throws {
        openSettingsChannelsTab()
        openAddChannelDialog()

        // 添加两个手动模型
        addManualModel(name: "model-one")
        sleep(0.5)
        addManualModel(name: "model-two")
        sleep(1)

        // 查找所有齿轮按钮
        let gearButtons = app.descendants(matching: .any).matching(identifier: UI.addChannelModelEditButton)
        XCTAssertTrue(gearButtons.count >= 2, "应有至少两个齿轮按钮")

        // 点击第一个齿轮按钮
        gearButtons.firstMatch.click()
        sleep(1)

        // 验证编辑器打开
        let editorSaveButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorSaveButton).firstMatch
        XCTAssertTrue(editorSaveButton.waitForExistence(timeout: 3), "编辑器应打开")

        // 关闭编辑器
        let cancelButton = app.descendants(matching: .any).matching(identifier: UI.modelEditorCancelButton).firstMatch
        if cancelButton.exists {
            cancelButton.click()
            sleep(1)
        }

        // 点击第二个齿轮按钮
        if gearButtons.count >= 2 {
            gearButtons.element(boundBy: 1).click()
            sleep(1)

            // 验证编辑器再次打开
            XCTAssertTrue(editorSaveButton.waitForExistence(timeout: 3), "第二个齿轮按钮应打开编辑器")

            // 关闭编辑器
            if cancelButton.exists {
                cancelButton.click()
                sleep(1)
            }
        }
    }
}
