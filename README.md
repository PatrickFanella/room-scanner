# Room Scanner

An iPhone and iPad app that scans a room with the LiDAR sensor and produces a
measured floor plan for contractors: wall lengths and heights, floor area,
net wall area with doors and windows subtracted, and exports to PDF, DXF, and
USDZ.

Scanning uses Apple's [RoomPlan](https://developer.apple.com/documentation/roomplan),
so it needs a LiDAR device (iPhone 12 Pro or later Pro models, or an iPad Pro
with LiDAR) running iOS 17 or later.

## What the first version does

- Projects stored on the device, one folder per project
- Scan a room; RoomPlan detects walls, doors, windows, openings, and the floor
- Floor plan with each wall labeled and dimensioned
- Room summary: floor area, ceiling height, perimeter, gross and net wall area
- Per-wall table; tap a wall to highlight it on the plan
- Replace any scanned length, the ceiling height, or the floor area with a
  tape measurement. Hand-entered values are marked `*` everywhere.
- Feet and inches (nearest 1/4") or metric
- Export a one-page PDF report, a DXF plan (inches or millimeters) for CAD,
  and the 3D model as USDZ
- Notes per project

## Layout

```
project.yml                  XcodeGen spec for the iOS app
App/                         SwiftUI + RoomPlan app (needs Xcode)
Packages/RoomGeometry/       Plain Swift package: geometry, measurements,
                             unit formatting and parsing, plan layout, DXF
```

`RoomGeometry` has no Apple framework dependencies, so its tests run on Linux
as well as macOS. The app converts RoomPlan's `CapturedRoom` into this model
(`App/RoomConverter.swift`) and stores the raw `CapturedRoom` JSON alongside it
so scans can be reprocessed later.

## Build

On a Mac with Xcode 16 or later:

```sh
brew install xcodegen
xcodegen generate
open RoomScanner.xcodeproj
```

Signing is set in `project.yml`: bundle identifier `tv.subcult.roomscanner`,
team `R5A689LLVY` (a free Personal Team). Set these there rather than in Xcode,
because `xcodegen generate` overwrites the Xcode project. Personal Team installs
expire after 7 days; rebuild from Xcode to renew. TestFlight and the App Store
need a paid Apple Developer Program team, which has a different team ID.

Run on a LiDAR device; the simulator cannot scan.

## Tests

```sh
cd Packages/RoomGeometry && swift test
```

Without a local toolchain:

```sh
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD/Packages/RoomGeometry:/src" -w /src swift:6.1-noble \
  swift test --scratch-path /tmp/build
```

## Check on a device

The app code has not been compiled yet; it was written on Linux. On the first
device run, check:

1. The project compiles under Xcode 16 (Swift 5 language mode, minimal
   concurrency checking).
2. The plan is not mirrored: walk a room with a known layout and compare.
   `RoomConverter` maps world `-z` to plan `y`.
3. The floor outline lines up with the walls. `RoomConverter.floorPolygon`
   assumes `polygonCorners` are in the floor's local coordinates and falls back
   to world coordinates if that reading sits farther from the walls.
4. The floor plan text in the app is upright (the Canvas Core Graphics context
   is assumed to be y-down, like the PDF context).
5. Scan accuracy. Apple does not publish RoomPlan tolerances. Tape-measure a
   few rooms and record the differences before quoting accuracy to customers.

## Next steps

- Several rooms combined into one floor plan (RoomPlan `StructureBuilder`)
- Photos and notes pinned to walls
- Materials estimates from the measured areas: drywall sheets, paint, flooring
  with a waste factor
- Cloud sync and sharing between crew members

## License

Original contributions in this repository are licensed under the GNU General
Public License, version 3 or (at your option) any later version
(`GPL-3.0-or-later`). See [LICENSE](LICENSE).

Third-party code, documentation, fonts, data, and other assets retain their own
licenses, copyright notices, and attribution. This license does not replace
those terms or grant rights to upstream material that its authors have not granted.
