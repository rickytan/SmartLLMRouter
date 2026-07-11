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
        static let menuProxyToggleButton = "menu.proxy.toggle"
        static let menuStatsLabel = "menu.statsLabel"
        static let menuFailoverToggle = "menu.failover.toggle"
        static let menuCopyEnvButton = "menu.copyEnvButton"
        static let menuSettingsButton = "menu.settingsButton"
        static let menuQuitButton = "menu.quitButton"
        static let menuRecentRequests = "menu.recentRequestsList"
        
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
        static let settingsSortBySpeedButton = "settings.channels.sortBySpeed"
        static let settingsChannelSearchField = "settings.channels.searchField"
        static let settingsChannelFilter = "settings.channels.filter"
        static let settingsChannelCount = "settings.channels.count"
        static let settingsImportConfigButton = "settings.channels.importConfig"
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
        
        // AddChannel
        static let addChannelHeaderClose = "addChannel.headerCloseButton"
        static let addChannelProviderPicker = "addChannel.providerPicker"
        static let addChannelProtocolPicker = "addChannel.protocolPicker"
        static let addChannelCustomNameField = "addChannel.customNameField"
        static let addChannelBaseUrlField = "addChannel.baseUrlField"
        static let addChannelApiKeyField = "addChannel.apiKeyField"
        static let addChannelPriorityField = "addChannel.priorityField"
        static let addChannelTestConnectionButton = "addChannel.testConnectionButton"
        static let addChannelFetchModelsButton = "addChannel.fetchModelsButton"
        static let addChannelManualModelField = "addChannel.manualModelField"
        static let addChannelModelEditButton = "addChannel.modelRow.editButton"
        static let addChannelModelDeleteButton = "addChannel.modelRow.deleteButton"
        static let addChannelSaveButton = "addChannel.saveButton"
        static let addChannelCancelButton = "addChannel.cancelButton"
        
        // ModelEditor
        static let modelEditorSaveButton = "modelEditor.saveButton"
        static let modelEditorCancelButton = "modelEditor.cancelButton"
        static let modelEditorCloseButton = "modelEditor.closeButton"
        static let modelEditorContextLengthField = "modelEditor.contextLengthField"
        static let modelEditorInputPriceField = "modelEditor.inputPriceField"
        static let modelEditorOutputPriceField = "modelEditor.outputPriceField"
        static let modelEditorVisionToggle = "modelEditor.visionToggle"

        // Onboarding
        static let onboardingTitle = "onboarding.welcome.title"
        static let onboardingWelcomeIcon = "onboarding.welcome.icon"
        static let onboardingWelcomeSubtitle = "onboarding.welcome.subtitle"
        static let onboardingSkipButton = "onboarding.skip"
        static let onboardingNextButton = "onboarding.welcome.nextButton"
        static let onboardingBackButton = "onboarding.back"
        static let onboardingAddChannelButton = "onboarding.addChannels.addButton"
        static let onboardingImportButton = "onboarding.addChannels.importButton"
        static let onboardingLaunchButton = "onboarding.done.launchButton"
        static let onboardingDoneTitle = "onboarding.done.title"
        static let onboardingDoneDescription = "onboarding.done.description"
        static let onboardingChannelDeleteButton = "onboarding.addChannels.channelRow.deleteButton"
        static let onboardingProgressWelcome = "onboarding.progress.welcome"
        static let onboardingProgressAddChannel = "onboarding.progress.addChannel"
        static let onboardingProgressShellConfig = "onboarding.progress.shellConfig"
        static let onboardingProgressDone = "onboarding.progress.done"
        static let onboardingWindowId = "onboarding"
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
