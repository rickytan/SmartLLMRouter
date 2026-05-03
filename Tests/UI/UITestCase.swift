import XCTest

/// UI Test 基类 - 封装 XCUIApplication 的启动和通用操作
/// 所有 UI 测试用例继承此类
class UITestCase: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        
        // 等待主窗口出现
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }
    
    // MARK: - Accessibility ID 常量
    /// 定义所有可测试元素的 accessibilityIdentifier
    enum UI {
        // MenuView
        static let menuStatusRunning = "menu.status.running"
        static let menuStatusStopped = "menu.status.stopped"
        static let menuPortLabel = "menu.port.label"
        static let menuFailoverToggle = "menu.failover.toggle"
        static let menuActiveChannel = "menu.active.channel"
        static let menuCopyEnvButton = "menu.copy环境变量"
        static let menuTestKeyButton = "menu测试密钥"
        static let menuSettingsButton = "menu.settings"
        static let menuQuitButton = "menu.quit"
        static let menuRecentRequests = "menu.recent.requests"
        
        // SettingsView
        static let settingsWindow = "settings.window"
        static let settingsGeneralTab = "settings.tab.general"
        static let settingsChannelsTab = "settings.tab.channels"
        static let settingsAdvancedTab = "settings.tab.advanced"
        static let settingsUsageTab = "settings.tab.usage"
        static let settingsAboutTab = "settings.tab.about"
        
        // General Tab
        static let settingsPortField = "settings.general.port"
        static let settingsStartServiceButton = "settings.general.start"
        static let settingsStopServiceButton = "settings.general.stop"
        static let settingsLaunchAtLoginToggle = "settings.general.launchAtLogin"
        
        // Channels Tab
        static let settingsAddChannelButton = "settings.channels.add"
        static let settingsTestAllButton = "settings.channels.testAll"
        static let settingsChannelList = "settings.channels.list"
        
        // Channel Row
        static let channelRowPrefix = "channel.row"
        static let channelNamePrefix = "channel.name"
        static let channelSpeedTestPrefix = "channel.speedtest"
        static let channelEditPrefix = "channel.edit"
        static let channelDeletePrefix = "channel.delete"
        static let channelStatusPrefix = "channel.status"
        
        // Advanced Tab
        static let settingsFailoverToggle = "settings.advanced.failover"
        static let settingsCooldown429 = "settings.advanced.cooldown.429"
        static let settingsCooldown5xx = "settings.advanced.cooldown.5xx"
        static let settingsCooldown401 = "settings.advanced.cooldown.401"
        
        // Usage Tab
        static let usageTotalRequests = "usage.totalRequests"
        static let usageTotalTokens = "usage.totalTokens"
        static let usageTotalCost = "usage.totalCost"
        
        // About Tab
        static let aboutVersionLabel = "about.version"
        static let aboutGithubButton = "about.github"
        
        // Common
        static let closeButton = "window.close"
        static let saveButton = "button.save"
        static let cancelButton = "button.cancel"
        static let deleteButton = "button.delete"
    }
    
    // MARK: - 辅助方法
    
    /// 等待元素出现
    func waitForElement(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "元素 '\(identifier)' 应在 \(timeout) 秒内出现")
        return element
    }
    
    /// 点击元素
    func tapElement(_ identifier: String) {
        let element = waitForElement(identifier)
        element.click()
    }
    
    /// 验证元素存在
    func assertElementExists(_ identifier: String, _ message: String = "") {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.exists, message.isEmpty ? "元素 '\(identifier)' 应存在" : message)
    }
    
    /// 验证元素不存在
    func assertElementNotExists(_ identifier: String, _ message: String = "") {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertFalse(element.exists, message.isEmpty ? "元素 '\(identifier)' 应不存在" : message)
    }
    
    /// 验证元素文本内容
    func assertElementText(_ identifier: String, equals expected: String) {
        let element = waitForElement(identifier)
        XCTAssertEqual(element.value as? String, expected, "元素 '\(identifier)' 文本应匹配")
    }
}
