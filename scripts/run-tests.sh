#!/bin/bash
# SmartLLMRouter - 测试运行脚本
# 用法: ./scripts/run-tests.sh [unit|ui|all]

set -e

cd "$(dirname "$0")/.."

export PATH="/opt/homebrew/opt/ruby@3.1/bin:$PATH"

SCHEME="SmartLLMRouter"
WORKSPACE="SmartLLMRouter.xcworkspace"
DESTINATION="platform=macOS,arch=arm64"

echo "🔧 生成项目..."
xcodegen generate --quiet

echo "📦 安装依赖..."
bundle exec pod install --quiet

echo "🏗️  构建..."
xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -destination "$DESTINATION" build -quiet

case "${1:-all}" in
    unit)
        echo "🧪 运行单元测试..."
        xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME" -destination "$DESTINATION" \
            -only-testing:SmartLLMRouterTests \
            2>&1 | grep -E '(Test|PASS|FAIL|passed|failed|Test Suite|Executed|error:)'
        ;;
    ui)
        echo "🖥️  运行 UI 测试..."
        xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME" -destination "$DESTINATION" \
            -only-testing:SmartLLMRouterUITests \
            2>&1 | grep -E '(Test|PASS|FAIL|passed|failed|Test Suite|Executed|error:)'
        ;;
    all)
        echo "🧪 运行所有测试..."
        xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME" -destination "$DESTINATION" \
            2>&1 | grep -E '(Test|PASS|FAIL|passed|failed|Test Suite|Executed|error:)'
        ;;
    *)
        echo "用法: $0 [unit|ui|all]"
        exit 1
        ;;
esac

echo "✅ 测试完成"
