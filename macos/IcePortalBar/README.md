# IcePortalBar 🚄

A small native macOS menubar app that shows live information from the Deutsche Bahn ICE Portal while you ride.

Where the Shiny dashboard focuses on collecting and plotting data over the whole trip, IcePortalBar focuses on what's happening *right now*:

- **Menu bar:** current speed, next stop with countdown, or current delay (configurable)
- **Next stop:** name, countdown, scheduled vs. expected arrival, platform (highlighting platform changes)
- **Delay:** forecast delay at the next stop plus any delay reasons for the rest of the trip
- **Trip progress:** percentage and distance travelled
- **Internet:** current connectivity quality and the forecast change ("→ Weak in 4 min")
- **Later stops:** compact timetable with delays and platforms
- **Speed sparkline:** a small rolling window of the last 20 minutes (nothing is persisted)

Like the dashboard, it **only** works while connected to the on-board `WIFIonICE` network.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or the Swift 5.9+ command line tools

## Run

```sh
cd macos/IcePortalBar
swift run
```

## Build an app bundle

```sh
cd macos/IcePortalBar
./scripts/build-app.sh
open build/IcePortalBar.app
```

Copy `build/IcePortalBar.app` into `/Applications` to keep it around. You can also open `Package.swift` in Xcode.

## Settings

The gear menu in the popover lets you choose what the menu bar shows (speed, next stop, delay or icon only) and how often to poll the API (5–60 seconds, default 10).
