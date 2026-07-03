# E2BBar

A small macOS menu bar app for watching your E2B sandboxes.

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

E2BBar calls `GET https://api.e2b.app/v2/sandboxes` with `X-API-Key`, using the current E2B v2 list sandboxes API.
