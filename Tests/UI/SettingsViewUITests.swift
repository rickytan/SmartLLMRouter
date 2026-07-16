import XCTest

/// SettingsView UI 测试 - 验证设置窗口各 Tab 的交互和数据绑定
final class SettingsViewUITests: UITestCase {
    
    // MARK: - 设置窗口基础测试
    
    /// 测试设置窗口可以打开和关闭
    func testSettingsWindowOpenAndClose() throws {
        // 打开设置窗口（通过菜单按钮或快捷键）
        app.activate()
        
        // macOS 设置窗口通常通过菜单栏或 NSApp 打开
        // 这里模拟通过菜单打开
        tapElement(UI.menuSettingsButton)
        
        // 等待设置窗口出现
        let settingsWindow = app.windows.firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), "设置窗口应出现")
        
        // 关闭窗口
        let closeButton = settingsWindow.buttons[UI.closeButton]
        if closeButton.exists {
            closeButton.click()
        } else {
            // 尝试按 Escape
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
        
        sleep(1)
        XCTAssertFalse(settingsWindow.exists, "设置窗口应关闭")
    }
    
    // MARK: - Tab 切换测试
    
    /// 测试所有 Tab 都存在并可切换
    func testAllTabsExist() throws {
        // 先打开设置窗口
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 验证 5 个 Tab 都存在
        let tabs = [
            UI.settingsGeneralTab,
            UI.settingsChannelsTab,
            UI.settingsAdvancedTab,
            UI.settingsUsageTab,
            UI.settingsAboutTab
        ]
        
        for tabIdentifier in tabs {
            let tab = app.descendants(matching: .any).matching(identifier: tabIdentifier).firstMatch
            XCTAssertTrue(tab.exists || tab.waitForExistence(timeout: 2), "Tab '\(tabIdentifier)' 应存在")
        }
    }
    
    /// 测试 General Tab 内容
    func testGeneralTabContent() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 点击 General Tab
        tapElement(UI.settingsGeneralTab)
        sleep(1)
        
        // 验证端口输入框存在
        assertElementExists(UI.settingsPortField, "General Tab 应包含端口输入框")
        
        // 验证服务控制按钮存在（启动或停止）
        let startExists = app.descendants(matching: .any).matching(identifier: UI.settingsStartServiceButton).firstMatch.exists
        let stopExists = app.descendants(matching: .any).matching(identifier: UI.settingsStopServiceButton).firstMatch.exists
        XCTAssertTrue(startExists || stopExists, "应显示服务控制按钮")
    }
    
    /// 测试 Channels Tab 内容
    func testChannelsTabContent() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 点击 Channels Tab
        tapElement(UI.settingsChannelsTab)
        sleep(1)
        
        // 验证添加频道按钮存在
        assertElementExists(UI.settingsAddChannelButton, "Channels Tab 应包含添加按钮")
        
        // 验证频道列表存在（即使为空）
        assertElementExists(UI.settingsChannelList, "Channels Tab 应包含频道列表")
    }
    
    /// 测试 Advanced Tab 内容
    func testAdvancedTabContent() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 点击 Advanced Tab
        tapElement(UI.settingsAdvancedTab)
        sleep(1)
        
        // 验证故障转移开关存在
        assertElementExists(UI.settingsFailoverToggle, "Advanced Tab 应包含故障转移开关")
        
        // 验证冷却时间设置存在
        assertElementExists(UI.settingsCooldown429, "应显示 429 冷却时间")
        assertElementExists(UI.settingsCooldown5xx, "应显示 5xx 冷却时间")
        assertElementExists(UI.settingsCooldown401, "应显示 401 冷却时间")
    }
    
    /// 测试 Usage Tab 内容
    func testUsageTabContent() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 点击 Usage Tab
        tapElement(UI.settingsUsageTab)
        sleep(1)
        
        // 验证统计卡片存在
        assertElementExists(UI.usageTotalRequests, "Usage Tab 应显示总请求数")
        assertElementExists(UI.usageTotalTokens, "Usage Tab 应显示总 Token 数")
        assertElementExists(UI.usageTotalCost, "Usage Tab 应显示总费用")
    }
    
    /// 测试 About Tab 内容
    func testAboutTabContent() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 点击 About Tab
        tapElement(UI.settingsAboutTab)
        sleep(1)
        
        // 验证版本信息存在
        assertElementExists(UI.aboutVersionLabel, "About Tab 应显示版本信息")
        
        // 验证 GitHub 按钮存在
        assertElementExists(UI.aboutGithubButton, "About Tab 应包含 GitHub 按钮")
        assertElementExists(UI.aboutReportIssueButton, "About Tab 应包含报告问题按钮")
    }
    
    // MARK: - 端口设置测试
    
    /// 测试端口输入框可以编辑和保存
    func testPortInputCanBeEdited() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 切换到 General Tab
        tapElement(UI.settingsGeneralTab)
        sleep(1)
        
        // 找到端口输入框
        let portField = app.descendants(matching: .any).matching(identifier: UI.settingsPortField).firstMatch
        XCTAssertTrue(portField.waitForExistence(timeout: 3), "端口输入框应存在")
        
        // 点击并清空（全选后删除）
        portField.click()
        portField.typeKey("a", modifierFlags: .command)
        portField.typeText(XCUIKeyboardKey.delete.rawValue)
        
        // 输入新端口
        portField.typeText("1898")
        
        // 验证输入成功
        XCTAssertEqual(portField.value as? String, "1898", "端口输入框应显示新值")
    }
}
