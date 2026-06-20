source "https://cdn.cocoapods.org/"
platform :osx, '13.0'

# Use static linking (no dynamic frameworks → smaller binary)
use_frameworks! :linkage => :static

target 'SmartLLMRouter' do
  # 轻量级 HTTP Server
  pod 'Swifter', '~> 1.5.0'
  # Keychain 管理
  pod 'KeychainAccess', '~> 4.2.2'
  # 应用更新检查
  pod 'Sparkle', '~> 2.6'

  # SwiftLint — Build phase linting
  pod 'SwiftLint'

  # 高性能异步日志系统
  pod 'CocoaLumberjack/Swift', '~> 3.8.5'

  # Unit tests inherit pods
  target 'SmartLLMRouterTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Fix unsupported Swift version
      config.build_settings['SWIFT_VERSION'] = '5.9'
      # Fix deployment target too low for Xcode 15
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    end
  end

end

post_integrate do |installer|
  installer.aggregate_targets.each do |aggregate_target|
    project = aggregate_target.user_project
    target = project.targets.find { |item| item.name == 'SmartLLMRouter' }
    next unless target

    phase = target.shell_script_build_phases.find { |item| item.name == 'Sign Sparkle Framework' }
    next unless phase

    target.build_phases.delete(phase)
    target.build_phases << phase
    project.save
  end
end
