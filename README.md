# Room Scanner

An iPhone and iPad app that scans a room with the LiDAR sensor and produces a
measured floor plan for contractors: wall lengths and heights, floor area, net
wall area with doors and windows subtracted, and exports to PDF, DXF and USDZ.

Scanning uses Apple's [RoomPlan](https://developer.apple.com/documentation/roomplan),
so it needs a LiDAR device (iPhone 12 Pro or a later Pro model, or an iPad Pro
with LiDAR) running iOS 17 or later.

Room Scanner is an early version (0.1.0). The app code has not yet been built
and run on a device, and there is no App Store or TestFlight release. Scan
accuracy has not been measured; Apple does not publish RoomPlan tolerances.

## Features

- Projects stored on the device, one folder per project, with notes
- Scan a room; RoomPlan detects walls, doors, windows, openings and the floor
- Floor plan with each wall labelled and dimensioned
- Room summary: floor area, ceiling height, perimeter, gross and net wall area
- Per-wall table; tap a wall to highlight it on the plan
- Replace any scanned length, the ceiling height or the floor area with a tape
  measurement. Hand-entered values are marked `*` everywhere.
- Feet and inches (nearest 1/4") or metric
- Export a one-page PDF report, a DXF plan (inches or millimetres) for CAD, and
  the 3D model as USDZ
- The raw RoomPlan scan is saved with each room, so scans can be reprocessed
  later

## Build

On a Mac with Xcode 16 or later:

```sh
brew install xcodegen
xcodegen generate
open RoomScanner.xcodeproj
```

The Xcode project is generated from `project.yml`, so change settings there:
`xcodegen generate` overwrites the Xcode project. Before building, set
`PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` in `project.yml` to your own
bundle identifier and Apple team. A free Personal Team works for installing on
your own device, but those installs expire after 7 days; TestFlight and the App
Store need a paid Apple Developer Program team.

Run on a LiDAR device. The simulator cannot scan.

## Tests

The geometry, measurement, unit and DXF code lives in a plain Swift package
with no Apple framework dependencies, so its tests run on Linux and macOS:

```sh
cd Packages/RoomGeometry && swift test
```

With Docker instead of a local Swift toolchain:

```sh
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD/Packages/RoomGeometry:/src" -w /src swift:6.1-noble \
  swift test --scratch-path /tmp/build
```

## First device run

Things to check the first time the app runs on a device:

1. The project compiles under Xcode 16 (Swift 5 language mode, minimal
   concurrency checking).
2. The plan is not mirrored: walk a room with a known layout and compare.
   `RoomConverter` maps world `-z` to plan `y`.
3. The floor outline lines up with the walls. `RoomConverter.floorPolygon`
   assumes `polygonCorners` are in the floor's local coordinates and falls back
   to world coordinates if that reading sits farther from the walls.
4. Text on the in-app floor plan is upright (the Canvas Core Graphics context is
   assumed to be y-down, like the PDF context).
5. Accuracy: tape-measure a few rooms and record the differences before quoting
   accuracy to anyone.

## Project layout

```text
project.yml                  XcodeGen spec for the iOS app
App/                         SwiftUI and RoomPlan app (needs Xcode)
Packages/RoomGeometry/       Swift package: geometry, measurements, unit
                             formatting and parsing, plan layout, DXF
```

The app converts RoomPlan's `CapturedRoom` into the `RoomGeometry` model in
`App/RoomConverter.swift`.

## Planned

- Several rooms combined into one floor plan (RoomPlan `StructureBuilder`)
- Photos and notes pinned to walls
- Materials estimates from the measured areas: drywall sheets, paint, flooring
  with a waste factor
- Cloud sync and sharing between crew members

## Contributing

Report bugs and request features in
[GitHub issues](https://github.com/subculture-collective/room-scanner/issues).
For code, open a pull request on GitHub against `main`. CI runs the `RoomGeometry`
package tests on every pull request, and they must pass before it merges. The
iOS app itself is not built in CI.

## License

Original contributions are licensed under the GNU General Public License,
version 3 or any later version (`GPL-3.0-or-later`). See [LICENSE](LICENSE).
Third-party code, fonts, data and other assets keep their own licences and
attribution.
