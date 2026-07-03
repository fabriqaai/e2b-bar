# E2BBar

A small macOS menu bar app for watching your E2B sandboxes.

Website: https://e2b.bar

## Run

```sh
swift run E2BBar
```

Open Settings from the menu bar item and save an E2B API key. For terminal launches you can also use:

```sh
E2B_API_KEY=... swift run E2BBar
```

## Build An App Bundle

```sh
make app
open build/E2BBar.app
```

## Build A DMG

```sh
make dmg
open build/E2BBar.dmg
```

## Website

The landing page is a single Cloudflare Worker in `worker/index.js`.
`e2b.bar` is the canonical domain; `e2bbar.app` and both `www` hosts redirect there.

Local deploy requires an authenticated Wrangler session:

```sh
wrangler login
wrangler deploy
```

GitHub Actions deploy uses these repository secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The site routes `/download` to the latest release asset:

```text
https://github.com/fabriqaai/e2b-bar/releases/latest/download/E2BBar.dmg
```

E2BBar calls `GET https://api.e2b.app/v2/sandboxes` with `X-API-Key`, using the current E2B v2 list sandboxes API.
