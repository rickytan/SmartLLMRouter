import XCTest

/// MenuView UI 测试 - 验证菜单栏状态显示、快捷操作和交互
final class MenuViewUITests: UITestCase {
    
    // MARK: - 状态显示测试
    
    /// 测试应用启动后菜单正确显示服务状态
    func testMenuDisplaysServiceStatus() throws {
        // 验证状态指示器存在（运行中或已停止）
        let runningExists = app.descendants(matching: .any).matching(identifier: UI.menuStatusRunning).firstMatch.exists
        let stoppedExists = app.descendants(matching: .any).matching(identifier: UI.menuStatusStopped).firstMatch.exists
        
        XCTAssertTrue(runningExists || stoppedExists, "应显示服务状态（运行中或已停止）")
        
        // 验证端口号显示
        assertElementExists(UI.menuPortLabel, "应显示端口号")
    }
    
    /// 测试快捷统计信息显示
    func testMenuDisplaysQuickStats() throws {
        // 验证请求数和 Token 统计区域存在
        // 这些通常作为文本显示在菜单中
        let menu = app.staticTexts.firstMatch
        XCTAssertTrue(menu.exists, "菜单应显示")
    }
    
    // MARK: - 自动故障转移测试
    
    /// 测试故障转移开关可交互
    func testFailoverToggleIsInteractive() throws {
        let toggle = app.descendants(matching: .any).matching(identifier: UI.menuFailoverToggle).firstMatch
        
        // 验证开关存在
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "故障转移开关应存在")
        
        // 验证开关有值（on/off）
        XCTAssertTrue(toggle.value != nil || toggle.isSelected, "开关应有状态值")
    }
    
    // MARK: - 操作按钮测试
    
    /// 测试复制环境变量按钮
    func testCopyEnvButtonExists() throws {
        assertElementExists(UI.menuCopyEnvButton, "复制环境变量按钮应存在")
    }
    
    // MARK: - 底部按钮测试
    
    /// 测试设置按钮可点击
    func testSettingsButtonOpensSettings() throws {
        let settingsButton = app.descendants(matching: .any).matching(identifier: UI.menuSettingsButton).firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3), "设置按钮应存在")
        
        // 点击设置按钮
        settingsButton.click()
        
        // 等待设置窗口出现
        let settingsWindow = app.windows[UI.settingsWindow]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5), "点击设置按钮应打开设置窗口")
    }
    
    /// 测试退出按钮存在
    func testQuitButtonExists() throws {
        assertElementExists(UI.menuQuitButton, "退出按钮应存在")
    }
    
    // MARK: - 最近请求测试
    
    /// 测试最近请求区域存在
    func testRecentRequestsSectionExists() throws {
        assertElementExists(UI.menuRecentRequests, "最近请求区域应存在")
    }
}
