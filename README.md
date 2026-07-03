# E2BBar

E2BBar is a native macOS menu bar app for keeping an eye on your E2B sandboxes without opening the browser. It shows running and paused sandboxes, resource totals, expiration timing, metadata, and quick links to E2B places you already use.

Website: https://e2b.bar

Latest DMG: https://github.com/fabriqaai/e2b-bar/releases/latest/download/E2BBar.dmg

Source: https://github.com/fabriqaai/e2b-bar

## What It Does

- Shows a compact menu bar counter for running sandboxes.
- Marks the menu bar item with an error indicator when refresh fails.
- Lists running and paused E2B sandboxes in a submenu.
- Shows sandbox display name, state, resource summary, short ID, expiration time, and metadata summary.
- Copies a sandbox ID when you click a sandbox row.
- Shows running, paused, fetched, and API-reported totals.
- Supports state filters for running, paused, or both.
- Supports an E2B metadata filter.
- Refreshes on a configurable interval.
- Refreshes immediately when the menu opens.
- Stores the API key in macOS Keychain.
- Can also read `E2B_API_KEY` from the launch environment for local development.
- Supports launch at login through macOS ServiceManagement.
- Provides quick links for the E2B dashboard, E2B docs, the app website, GitHub, and releases.

## Screens And Menus

E2BBar runs as an agent app, so it does not show a Dock icon. The main surface is the menu bar item.

The menu includes:

- Header with health and credential state.
- Running and paused totals.
- API fetch totals from the E2B response headers when available.
- Last refreshed time.
- Error text when the latest request fails.
- Sandboxes submenu.
- Refresh action.
- E2B dashboard and docs links.
- Settings.
- Quit.

The Settings window includes:

- General: state filter, metadata filter, refresh interval, launch at login, refresh, dashboard link.
- Account: credential status, API key save and clear actions, refresh, dashboard and docs links.
- About: app purpose, version, website, source, API endpoint, storage note, and external links.

## Requirements

- macOS 14 or newer.
- Swift 6 toolchain for local builds.
- An E2B API key that starts with `e2b_`.
- A GitHub release asset named `E2BBar.dmg` for the public download URL to work.

## Install

Download the latest release:

```text
https://github.com/fabriqaai/e2b-bar/releases/latest/download/E2BBar.dmg
```

Open the DMG, drag `E2BBar.app` to Applications, then launch it. Because the app is distributed outside the Mac App Store, macOS Gatekeeper expects the DMG and app to be signed and notarized by the release workflow.

If the direct download URL returns 404, the repository does not yet have a completed GitHub release with an `E2BBar.dmg` asset. Push a `v*` tag or run the release workflow from a tag to publish one.

## Configure E2B

Open E2BBar from the menu bar, choose Settings, then go to Account and paste your E2B API key.

The app validates that the key starts with `e2b_` and is followed by hexadecimal characters. Saved keys are stored in macOS Keychain under the service:

```text
com.hancengiz.e2bbar
```

For local development, you can also launch with:

```sh
E2B_API_KEY=e2b_your_key_here swift run E2BBar
```

The Keychain value takes precedence over the environment variable.

## E2B API Usage

E2BBar calls the E2B v2 sandboxes API:

```http
GET https://api.e2b.app/v2/sandboxes
X-API-Key: e2b_...
Accept: application/json
```

The app sends these query parameters:

- `limit`: capped at 100 per page.
- `state`: `running`, `paused`, or both as a comma-separated list.
- `metadata`: optional metadata filter from Settings.
- `nextToken`: pagination token from the `X-Next-Token` response header.

Pagination is followed for up to 20 pages. The app also reads `X-Total-Running` and `X-Total-Paused` headers when E2B returns them.

## Run Locally

Run from source:

```sh
swift run E2BBar
```

Run with an environment API key:

```sh
E2B_API_KEY=e2b_your_key_here swift run E2BBar
```

Build the release binary:

```sh
make build
```

Build and open the app bundle:

```sh
make run-app
```

Clean build outputs:

```sh
make clean
```

## Package Locally

Create an unsigned app bundle:

```sh
make app
open build/E2BBar.app
```

Create an unsigned DMG:

```sh
make dmg
open build/E2BBar.dmg
```

Local packaging scripts:

- `Scripts/package_app.sh`: builds the Swift executable and creates `build/E2BBar.app`.
- `Scripts/create_dmg.sh`: stages the app with an Applications symlink and creates `build/E2BBar.dmg`.

Local DMGs are useful for smoke testing. The public download should come from the GitHub release workflow because it signs, notarizes, staples, verifies, uploads, and publishes the DMG.

## Release

The release workflow is `.github/workflows/release.yml`.

It runs on:

- `push` tags matching `v*`.
- Manual `workflow_dispatch`.

Only tagged runs publish a GitHub release. Manual runs still build and upload the DMG as a workflow artifact, but they do not create the public release asset unless the ref is a tag.

Create the first notarized release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release job does this on `macos-15`:

- Builds the app bundle with `make app`.
- Imports the Developer ID Application certificate from `CSC_LINK`.
- Signs `build/E2BBar.app` with hardened runtime and timestamp.
- Creates `build/E2BBar.dmg`.
- Signs the DMG.
- Submits the DMG to Apple notarization with `notarytool`.
- Staples and validates the notarization ticket.
- Verifies the DMG with `hdiutil`.
- Uploads the DMG artifact.
- Publishes the GitHub release with `E2BBar.dmg`.

Required GitHub Actions secrets for notarized releases:

- `CSC_LINK`: base64 encoded Developer ID Application `.p12`.
- `CSC_KEY_PASSWORD`: password for that `.p12`.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for the Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

The stable download URL expected by the website is:

```text
https://github.com/fabriqaai/e2b-bar/releases/latest/download/E2BBar.dmg
```

## Website

The landing page is a single Cloudflare Worker in `worker/index.js`.

Canonical domain:

```text
https://e2b.bar
```

Redirects:

- `https://www.e2b.bar`
- `https://e2bbar.app`
- `https://www.e2bbar.app`

The Worker includes routes for:

- `/`: landing page.
- `/download`: redirects to the latest DMG release asset.
- `/github`: redirects to the repository.
- `/releases`: redirects to GitHub Releases.

Cloudflare config is in `wrangler.toml`.

## Deploy Website

The Worker deploy workflow is `.github/workflows/deploy-worker.yml`.

It runs on:

- Pushes to `main` that touch `worker/**`, `wrangler.toml`, or the workflow file.
- Manual `workflow_dispatch`.

Required GitHub Actions secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

`CLOUDFLARE_ACCOUNT_ID` can be a secret or a repository variable. The current workflow checks the variable first and falls back to the secret.

For local deploys, authenticate Wrangler:

```sh
wrangler login
wrangler deploy
```

For CI, use a Cloudflare token scoped to the account and zones that own `e2b.bar` and `e2bbar.app`. The token needs Workers deploy permissions and enough zone access for custom domains and DNS records.

## Repository Layout

```text
.
├── Sources/E2BBar/              # Native macOS app source
├── Resources/Info.plist         # App bundle metadata
├── Scripts/package_app.sh       # App bundle packaging
├── Scripts/create_dmg.sh        # DMG packaging
├── worker/index.js              # Cloudflare Worker landing page
├── wrangler.toml                # Worker routes and deploy config
├── .github/workflows/release.yml
├── .github/workflows/deploy-worker.yml
├── Makefile
└── Package.swift
```

Important Swift files:

- `E2BBarApp.swift`: application entry point.
- `StatusMenuController.swift`: menu bar item and menu construction.
- `AppModel.swift`: state, settings, refresh loop, credentials, app actions.
- `E2BClient.swift`: E2B API client.
- `Models.swift`: sandbox and API response models.
- `SettingsView.swift`: General, Account, and About settings tabs.
- `Keychain.swift`: Keychain persistence.
- `LaunchAtLoginManager.swift`: launch-at-login integration.

## Security Notes

- Do not commit API keys, Apple credentials, Cloudflare tokens, or certificate files.
- User E2B API keys are saved to macOS Keychain.
- GitHub Actions secrets are only referenced by name in workflows.
- The app calls E2B directly from the user's Mac; the landing page does not proxy API requests.
- `local-handoff/` is ignored for local operator notes that should not enter the public repo.

## Troubleshooting

`Invalid E2B API key format`

The app only accepts secret keys that start with `e2b_` followed by hexadecimal characters. Copy the secret key from the E2B dashboard.

`HTTP 401` or `authorization header is malformed`

The API key is missing, expired, pasted with extra characters, or not an E2B secret key. Clear the saved key in Settings and save a fresh one.

The menu shows no sandboxes

Check the state filter and metadata filter in Settings. The app defaults to running and paused sandboxes, but a metadata filter can narrow the list to zero.

The direct DMG URL returns 404

Create a tagged GitHub release and make sure the release contains an asset named `E2BBar.dmg`.

The website deploy succeeds but the domain does not resolve immediately

Check authoritative Cloudflare DNS first. Local resolvers can lag even after Cloudflare has the custom domain and DNS records.

## Current Scope

E2BBar is intentionally small. It is meant to be a fast menu bar companion for visibility and links, not a full dashboard replacement. The current app lists and filters sandboxes, copies IDs, opens external surfaces, and keeps credentials local.

Useful future additions:

- Sandbox kill/pause/resume actions when the API surface is wired safely.
- Per-sandbox dashboard or terminal links if E2B exposes stable URLs.
- Search inside the menu.
- Template or team grouping.
- Notifications before sandbox expiration.
- Signed Sparkle updates if distribution moves beyond GitHub Releases.
