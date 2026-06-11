# Sentry Setup

The repository-side Sentry integration is already configured. It is disabled in
Debug builds and in Release builds that do not contain a DSN. This keeps forks,
pull requests, and contributor builds from sending events to the official
project.

## 1. Create the Sentry organization and project

1. Sign in at <https://sentry.io/>.
2. Create an organization for DumpertTV, or use an existing organization.
3. Create a project using the Apple/tvOS platform.
4. Use a clear project slug, for example `dumpert-tvos`.
5. Copy these values:
   - Organization slug
   - Project slug
   - Project DSN from **Project Settings > Client Keys (DSN)**

The DSN identifies the ingest endpoint and is not an administrative credential.
It is still injected through Xcode Cloud so forks do not accidentally report to
the official project.

Apply for Sentry's open-source sponsorship after the project exists:
<https://sentry.io/for/open-source/>.

## 2. Create the debug-file upload token

Create an Organization Token in Sentry for `sentry-cli`. Give it access to the
DumpertTV project and debug-information-file uploads. Copy the token when Sentry
shows it; this token is a secret and must never be committed.

Sentry CLI authentication documentation:
<https://docs.sentry.io/cli/configuration/>

## 3. Configure Xcode Cloud

In App Store Connect:

1. Open **My Apps > DumpertTV > Xcode Cloud**.
2. Open the workflow that archives and distributes the TestFlight build.
3. Open **Environment** and add:

| Variable | Value | Secret |
|---|---|---|
| `SENTRY_DSN` | Project DSN | Recommended |
| `SENTRY_AUTH_TOKEN` | Organization Token | Yes |
| `SENTRY_ORG` | Organization slug | No |
| `SENTRY_PROJECT` | Project slug | No |

The existing scripts then perform the remaining work:

- `ci_post_clone.sh` writes the DSN into the temporary build configuration,
  installs `sentry-cli`, and generates the Xcode project.
- `ci_post_xcodebuild.sh` uploads archive dSYMs and source context.

Do not add these values to `project.yml`, source files, or a committed
`.xcconfig`.

## 4. Run the first Xcode Cloud archive

Start the TestFlight archive workflow. Check the build logs for:

```text
Configuring Sentry DSN for this build...
Installing sentry-cli...
Uploading debug files to Sentry...
```

In Sentry, open **Project Settings > Debug Files** and confirm that debug files
from the new build appear. The upload intentionally fails the archive when
credentials are configured but dSYMs cannot be found or uploaded; releasing an
unsymbolicated build would make native crash reports significantly less useful.

## 5. Verify event delivery locally

Create the ignored file `Config/Sentry.local.xcconfig`:

```xcconfig
SENTRY_DSN = https:/$()/PUBLIC_KEY@HOST/PROJECT_ID
```

The unusual `/$()/` sequence is required by xcconfig syntax and becomes `//`
during build-setting expansion.

Then:

1. Run `xcodegen generate`.
2. Edit the Dumpert scheme.
3. Set **Run > Build Configuration** to `Release`.
4. Add the launch argument `--sentry-test-event`.
5. Run the app.
6. Confirm the event named `DumpertTV Sentry integration test` appears.
7. Remove the launch argument and local configuration file.

Debug builds never initialize Sentry, even when a local DSN is present.

## 6. Verify a real crash

After the nonfatal test succeeds, use a TestFlight build to verify native crash
reporting. Trigger a deliberate crash only in a temporary test branch and
without the Xcode debugger attached. Relaunch the app afterward so the SDK can
send the stored event.

Confirm that:

- The event is assigned to the correct release.
- Stack frames contain function names and line information.
- Sentry does not report missing debug files.

Remove the deliberate crash before merging.

## 7. Configure the Sentry project

Recommended initial settings:

1. Enable alerts for new issues and regressions.
2. Enable spike protection and set a usage limit.
3. Configure data scrubbing for authorization headers, cookies, query strings,
   email addresses, IP addresses, and CloudKit identifiers.
4. Restrict project membership to maintainers who triage production issues.
5. Require two-factor authentication for the organization.
6. Keep performance tracing, profiling, logs, and replay disabled initially.

The app-side configuration already:

- Sets `sendDefaultPii` to `false`.
- Disables automatic network breadcrumbs and failed-request capture.
- Disables screenshots and view-hierarchy attachments.
- Sets tracing sample rate to zero.
- Uses Sentry only in non-Debug builds with a configured DSN.

## 8. Privacy and release process

Before distributing the first Sentry-enabled build:

1. Update the public privacy policy to disclose crash and diagnostic reporting
   to Sentry.
2. Review App Store Connect's App Privacy answers for crash and diagnostic data.
3. Confirm the Sentry data-retention period and region meet project policy.
4. Avoid adding video titles, search queries, CloudKit record names, device
   identifiers, or full API URLs as Sentry tags, breadcrumbs, or messages.

For every release, verify that the Xcode Cloud debug-file upload completed.
Use Xcode Organizer alongside Sentry because Apple diagnostics can still contain
platform-specific information that third-party reporting does not.

## Relevant files

- `project.yml`
- `Config/Package.resolved`
- `Config/Release.xcconfig`
- `Dumpert/Utilities/SentryMonitoring.swift`
- `ci_scripts/ci_post_clone.sh`
- `ci_scripts/ci_post_xcodebuild.sh`

Official references:

- <https://docs.sentry.io/platforms/apple/guides/tvos/>
- <https://docs.sentry.io/platforms/apple/dsym/>
- <https://docs.sentry.io/cli/dif/>
- <https://developer.apple.com/documentation/xcode/writing-custom-build-scripts>
