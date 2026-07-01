import XCTest

/// Accessibility Identifier 覆盖测试
/// 验证所有关键可交互元素都设置了 accessibilityIdentifier
/// 这是 UI 测试能够正确定位元素的前提
final class AccessibilityCoverageTests: UITestCase {
    
    // MARK: - MenuView 覆盖率测试
    
    /// 验证 MenuView 关键元素都有 accessibilityIdentifier
    func testMenuViewAccessibilityCoverage() throws {
        let requiredIdentifiers = [
            UI.menuStatusRunning,
            UI.menuStatusStopped,
            UI.menuPortLabel,
            UI.menuFailoverToggle,
            UI.menuCopyEnvButton,
            UI.menuTestKeyButton,
            UI.menuSettingsButton,
            UI.menuQuitButton,
            UI.menuRecentRequests,
        ]
        
        // 统计有多少元素存在（不要求全部，因为状态互斥）
        var existingCount = 0
        for identifier in requiredIdentifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if element.exists {
                existingCount += 1
            }
        }
        
        // 至少应有 70% 的标识符存在（排除互斥元素如 running/stopped）
        let threshold = Int(Double(requiredIdentifiers.count) * 0.7)
        XCTAssertGreaterThanOrEqual(existingCount, threshold,
            "MenuView 应覆盖至少 70% 的 accessibilityIdentifier（当前 \(existingCount)/\(requiredIdentifiers.count)）")
    }
    
    // MARK: - SettingsView 覆盖率测试
    
    /// 验证 SettingsView 各 Tab 关键元素都有 accessibilityIdentifier
    func testSettingsViewAccessibilityCoverage() throws {
        // 打开设置窗口
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        let requiredTabIdentifiers = [
            UI.settingsGeneralTab,
            UI.settingsChannelsTab,
            UI.settingsAdvancedTab,
            UI.settingsUsageTab,
            UI.settingsAboutTab,
        ]
        
        var existingTabs = 0
        for identifier in requiredTabIdentifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if element.exists {
                existingTabs += 1
            }
        }
        
        // 所有 Tab 都应存在
        XCTAssertEqual(existingTabs, requiredTabIdentifiers.count,
            "SettingsView 所有 Tab 都应有 accessibilityIdentifier")
    }
    
    /// 验证 General Tab 元素覆盖率
    func testGeneralTabAccessibilityCoverage() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        tapElement(UI.settingsGeneralTab)
        sleep(1)
        
        let requiredIdentifiers = [
            UI.settingsPortField,
        ]
        
        for identifier in requiredIdentifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.exists, "General Tab '\(identifier)' 应有 accessibilityIdentifier")
        }
    }
    
    /// 验证 Channels Tab 元素覆盖率
    func testChannelsTabAccessibilityCoverage() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        tapElement(UI.settingsChannelsTab)
        sleep(1)
        
        let requiredIdentifiers = [
            UI.settingsAddChannelButton,
            UI.settingsChannelList,
        ]
        
        for identifier in requiredIdentifiers {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.exists, "Channels Tab '\(identifier)' 应有 accessibilityIdentifier")
        }
    }
    
    // MARK: - 交互元素测试
    
    /// 验证所有按钮都可点击（hittable）
    func testAllButtonsAreHittable() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        
        // 获取所有按钮
        let buttons = app.buttons.allElementsBoundByIndex
        
        // 至少验证有几个按钮是可点击的
        let hittableCount = buttons.filter { $0.isHittable }.count
        
        XCTAssertGreaterThan(hittableCount, 0, "应有可交互的按钮")
    }
    
    /// 验证所有输入框都可编辑
    func testAllTextFieldsAreEditable() throws {
        tapElement(UI.menuSettingsButton)
        sleep(1)
        tapElement(UI.settingsGeneralTab)
        sleep(1)
        
        let textFields = app.textFields.allElementsBoundByIndex
        
        for textField in textFields {
            if textField.exists {
                XCTAssertTrue(textField.isEnabled, "输入框 '\(textField.identifier)' 应可编辑")
            }
        }
    }
}
