#!/bin/sh
set -e

echo "Installing XcodeGen..."
brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -n "${SENTRY_DSN:-}" ]; then
    echo "Configuring Sentry DSN for this build..."
    escaped_sentry_dsn=$(printf '%s' "$SENTRY_DSN" | sed 's#://#:/$()/#')
    printf 'SENTRY_DSN = %s\n' "$escaped_sentry_dsn" > Config/Sentry.local.xcconfig
fi

if [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
    echo "Installing sentry-cli..."
    brew install getsentry/tools/sentry-cli
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Installing resolved Swift package versions..."
swiftpm_directory="Dumpert.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$swiftpm_directory"
cp Config/Package.resolved "$swiftpm_directory/Package.resolved"

echo "Done — Dumpert.xcodeproj generated"
