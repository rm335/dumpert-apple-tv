#!/bin/sh
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    echo "Skipping Sentry debug-file upload for non-archive action."
    exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] ||
   [ -z "${SENTRY_ORG:-}" ] ||
   [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "Skipping Sentry debug-file upload: configuration is incomplete."
    exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
    echo "error: sentry-cli is unavailable; debug files were not uploaded."
    exit 1
fi

if [ -n "${CI_ARCHIVE_PATH:-}" ] && [ -d "$CI_ARCHIVE_PATH/dSYMs" ]; then
    debug_files_path="$CI_ARCHIVE_PATH/dSYMs"
elif [ -n "${DWARF_DSYM_FOLDER_PATH:-}" ] && [ -d "$DWARF_DSYM_FOLDER_PATH" ]; then
    debug_files_path="$DWARF_DSYM_FOLDER_PATH"
else
    echo "error: unable to locate the archive dSYM directory."
    exit 1
fi

echo "Uploading debug files to Sentry..."
sentry-cli debug-files upload \
    --include-sources \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$debug_files_path"
