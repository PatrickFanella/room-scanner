import Foundation

/// Values the user measured by hand. They replace the scanned values in every
/// calculation and export; the scan itself is kept unchanged.
public struct MeasurementOverrides: Codable, Hashable, Sendable {
    /// Wall lengths in meters, keyed by wall UUID string.
    public var wallLengths: [String: Double]
    /// Ceiling height in meters, applied to every wall.
    public var ceilingHeight: Double?
    /// Floor area in square meters.
    public var floorArea: Double?

    public init(wallLengths: [String: Double] = [:], ceilingHeight: Double? = nil, floorArea: Double? = nil) {
        self.wallLengths = wallLengths
        self.ceilingHeight = ceilingHeight
        self.floorArea = floorArea
    }

    public func wallLength(for id: UUID) -> Double? { wallLengths[id.uuidString] }

    public mutating func setWallLength(_ meters: Double?, for id: UUID) {
        wallLengths[id.uuidString] = meters
    }

    public var isEmpty: Bool { wallLengths.isEmpty && ceilingHeight == nil && floorArea == nil }
}

public struct WallMeasurement: Hashable, Identifiable, Sendable {
    public var id: UUID
    /// "A", "B", … "Z", "AA", …
    public var label: String
    public var length: Double
    public var height: Double
    public var grossArea: Double
    public var openingArea: Double
    public var netArea: Double
    public var openingCount: Int
    public var lengthIsOverridden: Bool
}

public struct RoomMeasurements: Hashable, Sendable {
    public var walls: [WallMeasurement]
    /// Square meters, or nil when neither the scan nor the user supplied it.
    public var floorArea: Double?
    public var floorAreaIsOverridden: Bool
    public var ceilingHeight: Double
    public var ceilingHeightIsOverridden: Bool
    public var perimeter: Double
    public var grossWallArea: Double
    public var netWallArea: Double
    public var doorCount: Int
    public var windowCount: Int
    public var openingCount: Int

    public func wall(_ id: UUID) -> WallMeasurement? { walls.first { $0.id == id } }
}

public enum MeasurementCalculator {
    /// Openings without a reported wall attach to the nearest wall within this distance.
    public static let openingAttachTolerance = 0.3

    public static func measure(_ room: Room, overrides: MeasurementOverrides = .init()) -> RoomMeasurements {
        let assignment = assignOpenings(room)
        let scannedCeiling = median(room.walls.map(\.height)) ?? 0
        let ceiling = overrides.ceilingHeight ?? scannedCeiling

        let walls = room.walls.enumerated().map { index, wall -> WallMeasurement in
            let overriddenLength = overrides.wallLength(for: wall.id)
            let length = overriddenLength ?? wall.length
            let height = overrides.ceilingHeight ?? wall.height
            let gross = length * height
            let openings = room.openings.filter { assignment[$0.id] == wall.id }
            let openingArea = min(gross, openings.reduce(0) { $0 + $1.area })
            return WallMeasurement(
                id: wall.id,
                label: wallLabel(index),
                length: length,
                height: height,
                grossArea: gross,
                openingArea: openingArea,
                netArea: gross - openingArea,
                openingCount: openings.count,
                lengthIsOverridden: overriddenLength != nil
            )
        }

        let scannedFloor = room.floorPolygon.count >= 3 ? Geometry.polygonArea(room.floorPolygon) : nil

        return RoomMeasurements(
            walls: walls,
            floorArea: overrides.floorArea ?? scannedFloor,
            floorAreaIsOverridden: overrides.floorArea != nil,
            ceilingHeight: ceiling,
            ceilingHeightIsOverridden: overrides.ceilingHeight != nil,
            perimeter: walls.reduce(0) { $0 + $1.length },
            grossWallArea: walls.reduce(0) { $0 + $1.grossArea },
            netWallArea: walls.reduce(0) { $0 + $1.netArea },
            doorCount: room.openings.filter { $0.kind == .door }.count,
            windowCount: room.openings.filter { $0.kind == .window }.count,
            openingCount: room.openings.filter { $0.kind == .opening }.count
        )
    }

    /// Maps each opening to a wall: the reported wall if it exists, otherwise the nearest wall
    /// within `openingAttachTolerance`. Unmatched openings are left out.
    public static func assignOpenings(_ room: Room) -> [UUID: UUID] {
        let wallIDs = Set(room.walls.map(\.id))
        var result: [UUID: UUID] = [:]
        for opening in room.openings {
            if let id = opening.wallID, wallIDs.contains(id) {
                result[opening.id] = id
                continue
            }
            let nearest = room.walls
                .map { ($0.id, Geometry.distance(from: opening.midpoint, toSegment: $0.start, $0.end)) }
                .min { $0.1 < $1.1 }
            if let nearest, nearest.1 <= openingAttachTolerance {
                result[opening.id] = nearest.0
            }
        }
        return result
    }

    public static func wallLabel(_ index: Int) -> String {
        var n = index
        var label = ""
        repeat {
            label = String(UnicodeScalar(UInt8(65 + n % 26))) + label
            n = n / 26 - 1
        } while n >= 0
        return label
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
