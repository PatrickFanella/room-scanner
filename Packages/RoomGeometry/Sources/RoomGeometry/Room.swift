import Foundation

/// A point on the floor plan, in meters. `x` is world x; `y` is world -z,
/// so the plan reads as a top-down view without mirroring.
public struct Point2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Point2, s: Double) -> Point2 { Point2(x: a.x * s, y: a.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2) -> Double { (self - other).length }
}

public struct Wall: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: Point2
    public var end: Point2
    /// Scanned wall height in meters.
    public var height: Double

    public init(id: UUID = UUID(), start: Point2, end: Point2, height: Double) {
        self.id = id
        self.start = start
        self.end = end
        self.height = height
    }

    public var length: Double { start.distance(to: end) }
    public var midpoint: Point2 { (start + end) * 0.5 }
}

public enum OpeningKind: String, Codable, Sendable {
    case door
    case window
    case opening
}

/// A door, window, or open passage in a wall.
public struct Opening: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: OpeningKind
    /// The wall this opening belongs to, when the scanner reported one.
    public var wallID: UUID?
    public var start: Point2
    public var end: Point2
    public var height: Double

    public init(id: UUID = UUID(), kind: OpeningKind, wallID: UUID?, start: Point2, end: Point2, height: Double) {
        self.id = id
        self.kind = kind
        self.wallID = wallID
        self.start = start
        self.end = end
        self.height = height
    }

    public var width: Double { start.distance(to: end) }
    public var area: Double { width * height }
    public var midpoint: Point2 { (start + end) * 0.5 }
}

/// Scanned room geometry, independent of RoomPlan so it can be stored and tested anywhere.
public struct Room: Codable, Hashable, Sendable {
    public var walls: [Wall]
    public var openings: [Opening]
    /// Floor outline. Empty when the scanner did not report one.
    public var floorPolygon: [Point2]

    public init(walls: [Wall], openings: [Opening], floorPolygon: [Point2]) {
        self.walls = walls
        self.openings = openings
        self.floorPolygon = floorPolygon
    }

    public var allPoints: [Point2] {
        walls.flatMap { [$0.start, $0.end] } + openings.flatMap { [$0.start, $0.end] } + floorPolygon
    }

    public var bounds: Bounds? { Bounds(points: allPoints) }

    /// Center used to decide which side of a wall is "outside" for labels.
    public var center: Point2 {
        let points = floorPolygon.isEmpty ? walls.flatMap { [$0.start, $0.end] } : floorPolygon
        guard !points.isEmpty else { return Point2(x: 0, y: 0) }
        let sum = points.reduce(Point2(x: 0, y: 0), +)
        return sum * (1 / Double(points.count))
    }
}

public struct Bounds: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init?(points: [Point2]) {
        guard let first = points.first else { return nil }
        var b = (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() {
            b.minX = min(b.minX, p.x)
            b.minY = min(b.minY, p.y)
            b.maxX = max(b.maxX, p.x)
            b.maxY = max(b.maxY, p.y)
        }
        minX = b.minX
        minY = b.minY
        maxX = b.maxX
        maxY = b.maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
}

public enum Geometry {
    /// Area of a simple polygon (shoelace formula). Winding order does not matter.
    public static func polygonArea(_ points: [Point2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Shortest distance from `p` to the segment `a`–`b`.
    public static func distance(from p: Point2, toSegment a: Point2, _ b: Point2) -> Double {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
        return p.distance(to: a + ab * t)
    }
}
