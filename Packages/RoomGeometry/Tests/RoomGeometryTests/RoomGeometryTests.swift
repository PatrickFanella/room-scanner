import Foundation
import XCTest
@testable import RoomGeometry

/// A 4 m × 3 m room, 2.5 m high, with a door on wall A, a window near wall B that the
/// scanner did not attach to a wall, and one stray opening far from every wall.
func sampleRoom() -> Room {
    let p = { (x: Double, y: Double) in Point2(x: x, y: y) }
    let a = Wall(start: p(0, 0), end: p(4, 0), height: 2.5)
    let b = Wall(start: p(4, 0), end: p(4, 3), height: 2.5)
    let c = Wall(start: p(4, 3), end: p(0, 3), height: 2.5)
    let d = Wall(start: p(0, 3), end: p(0, 0), height: 2.5)
    return Room(
        walls: [a, b, c, d],
        openings: [
            Opening(kind: .door, wallID: a.id, start: p(1, 0), end: p(1.9, 0), height: 2.0),
            Opening(kind: .window, wallID: nil, start: p(4.05, 1), end: p(4.05, 2.2), height: 1.0),
            Opening(kind: .opening, wallID: nil, start: p(10, 10), end: p(11, 10), height: 2.0),
        ],
        floorPolygon: [p(0, 0), p(4, 0), p(4, 3), p(0, 3)]
    )
}

final class MeasurementTests: XCTestCase {
    func testPolygonArea() {
        let room = sampleRoom()
        XCTAssertEqual(Geometry.polygonArea(room.floorPolygon), 12, accuracy: 1e-9)
        XCTAssertEqual(Geometry.polygonArea(room.floorPolygon.reversed()), 12, accuracy: 1e-9)
        XCTAssertEqual(Geometry.polygonArea([Point2(x: 0, y: 0), Point2(x: 1, y: 1)]), 0)
    }

    func testRoomMeasurements() {
        let m = MeasurementCalculator.measure(sampleRoom())
        XCTAssertEqual(m.walls.map(\.label), ["A", "B", "C", "D"])
        XCTAssertEqual(m.perimeter, 14, accuracy: 1e-9)
        XCTAssertEqual(m.floorArea ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(m.ceilingHeight, 2.5, accuracy: 1e-9)

        XCTAssertEqual(m.walls[0].grossArea, 10, accuracy: 1e-9)
        XCTAssertEqual(m.walls[0].netArea, 8.2, accuracy: 1e-9)
        // Window attached to wall B by proximity.
        XCTAssertEqual(m.walls[1].openingCount, 1)
        XCTAssertEqual(m.walls[1].netArea, 6.3, accuracy: 1e-9)
        XCTAssertEqual(m.grossWallArea, 35, accuracy: 1e-9)
        XCTAssertEqual(m.netWallArea, 32, accuracy: 1e-9)
        XCTAssertEqual(m.doorCount, 1)
        XCTAssertEqual(m.windowCount, 1)
        XCTAssertEqual(m.openingCount, 1)
    }

    func testOverridesReplaceScannedValues() {
        let room = sampleRoom()
        var overrides = MeasurementOverrides(ceilingHeight: 3.0, floorArea: 12.5)
        overrides.setWallLength(4.1, for: room.walls[0].id)
        let m = MeasurementCalculator.measure(room, overrides: overrides)

        XCTAssertTrue(m.walls[0].lengthIsOverridden)
        XCTAssertFalse(m.walls[1].lengthIsOverridden)
        XCTAssertEqual(m.walls[0].grossArea, 4.1 * 3.0, accuracy: 1e-9)
        XCTAssertEqual(m.walls[1].height, 3.0, accuracy: 1e-9)
        XCTAssertEqual(m.floorArea ?? 0, 12.5, accuracy: 1e-9)
        XCTAssertTrue(m.floorAreaIsOverridden)
        XCTAssertEqual(m.perimeter, 14.1, accuracy: 1e-9)
    }

    func testOpeningAreaNeverExceedsWall() {
        var room = sampleRoom()
        room.openings = [Opening(kind: .opening, wallID: room.walls[0].id,
                                 start: Point2(x: 0, y: 0), end: Point2(x: 4, y: 0), height: 9)]
        let m = MeasurementCalculator.measure(room)
        XCTAssertEqual(m.walls[0].netArea, 0, accuracy: 1e-9)
    }

    func testMissingFloorPolygon() {
        var room = sampleRoom()
        room.floorPolygon = []
        XCTAssertNil(MeasurementCalculator.measure(room).floorArea)
    }

    func testWallLabels() {
        XCTAssertEqual(MeasurementCalculator.wallLabel(0), "A")
        XCTAssertEqual(MeasurementCalculator.wallLabel(25), "Z")
        XCTAssertEqual(MeasurementCalculator.wallLabel(26), "AA")
        XCTAssertEqual(MeasurementCalculator.wallLabel(27), "AB")
    }

    func testOverridesRoundTripThroughJSON() throws {
        var overrides = MeasurementOverrides(ceilingHeight: 2.4)
        overrides.setWallLength(3.2, for: UUID())
        let data = try JSONEncoder().encode(overrides)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementOverrides.self, from: data), overrides)
    }
}

final class UnitTests: XCTestCase {
    func testFormatImperial() {
        XCTAssertEqual(Units.formatLength(147.5 * Units.metersPerInch, .imperial), "12' 3 1/2\"")
        XCTAssertEqual(Units.formatLength(Units.metersPerFoot, .imperial), "1' 0\"")
        // 11.996 in rounds up to a full foot.
        XCTAssertEqual(Units.formatLength(0.3047, .imperial), "1' 0\"")
        XCTAssertEqual(Units.formatLength(6.75 * Units.metersPerInch, .imperial), "0' 6 3/4\"")
        XCTAssertEqual(Units.formatArea(12, .imperial), "129.2 sq ft")
    }

    func testFormatMetric() {
        XCTAssertEqual(Units.formatLength(3.7465, .metric), "3.75 m")
        XCTAssertEqual(Units.formatArea(12, .metric), "12.00 m²")
    }

    func testParseImperial() throws {
        let expected = 147.5 * Units.metersPerInch
        for input in ["12' 3 1/2\"", "12'3 1/2\"", "12' 3.5\"", "12ft 3.5in", "147.5\"", "12' 3-1/2\""] {
            let value = try XCTUnwrap(Units.parseLength(input, .imperial), input)
            XCTAssertEqual(value, expected, accuracy: 1e-9, input)
        }
        XCTAssertEqual(Units.parseLength("12.5", .imperial) ?? 0, 12.5 * Units.metersPerFoot, accuracy: 1e-9)
        XCTAssertEqual(Units.parseLength("8'", .imperial) ?? 0, 8 * Units.metersPerFoot, accuracy: 1e-9)
        XCTAssertEqual(Units.parseLength("1/2\"", .imperial) ?? 0, 0.5 * Units.metersPerInch, accuracy: 1e-9)
        XCTAssertNil(Units.parseLength("", .imperial))
        XCTAssertNil(Units.parseLength("abc", .imperial))
        XCTAssertNil(Units.parseLength("0", .imperial))
        XCTAssertNil(Units.parseLength("3 1/0\"", .imperial))
    }

    func testParseMetric() {
        XCTAssertEqual(Units.parseLength("3.5", .metric) ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(Units.parseLength("3.5 m", .metric) ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(Units.parseLength("350 cm", .metric) ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(Units.parseLength("3500mm", .metric) ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertNil(Units.parseLength("-2", .metric))
    }

    func testParseArea() {
        XCTAssertEqual(Units.parseArea("129.17 sq ft", .imperial) ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(Units.parseArea("1,000", .imperial) ?? 0, 1000 * Units.squareMetersPerSquareFoot, accuracy: 1e-9)
        XCTAssertEqual(Units.parseArea("12 m²", .metric) ?? 0, 12, accuracy: 1e-9)
        XCTAssertNil(Units.parseArea("lots", .metric))
    }
}

final class LayoutTests: XCTestCase {
    func testFitKeepsPlanInsidePaddedArea() throws {
        let room = sampleRoom()
        var withoutStray = room
        withoutStray.openings.removeLast()
        let bounds = try XCTUnwrap(withoutStray.bounds)
        let t = PlanTransform.fit(bounds, width: 400, height: 300, padding: 20)
        for p in withoutStray.allPoints.map(t.apply) {
            XCTAssertGreaterThanOrEqual(p.x, 20 - 1e-9)
            XCTAssertLessThanOrEqual(p.x, 380 + 1e-9)
            XCTAssertGreaterThanOrEqual(p.y, 20 - 1e-9)
            XCTAssertLessThanOrEqual(p.y, 280 + 1e-9)
        }
        // Plan y up becomes drawing y down.
        XCTAssertLessThan(t.apply(Point2(x: 0, y: 3)).y, t.apply(Point2(x: 0, y: 0)).y)
    }

    func testLabelsSitOutsideAndReadUpright() {
        let room = sampleRoom()
        let center = room.center
        for wall in room.walls {
            let placement = PlanLayout.labelPlacement(for: wall, roomCenter: center, offset: 0.25)
            XCTAssertGreaterThan(placement.dimensionAnchor.distance(to: center), wall.midpoint.distance(to: center))
            XCTAssertLessThan(placement.letterAnchor.distance(to: center), wall.midpoint.distance(to: center))
            XCTAssertLessThanOrEqual(abs(placement.angle), .pi / 2 + 1e-9)
        }
        let c = PlanLayout.labelPlacement(for: room.walls[2], roomCenter: center, offset: 0.25)
        XCTAssertEqual(c.angle, 0, accuracy: 1e-9)
        XCTAssertEqual(c.dimensionAnchor.y, 3.25, accuracy: 1e-9)
    }
}

final class DXFTests: XCTestCase {
    func testDXFStructure() {
        let room = sampleRoom()
        let m = MeasurementCalculator.measure(room)
        let dxf = DXFWriter.write(room, measurements: m, units: .imperial)
        let lines = dxf.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(dxf.contains("AC1009"))
        XCTAssertEqual(lines.suffix(3), ["0", "EOF", ""])
        // Group codes and values alternate, so the line count must be even.
        XCTAssertEqual((lines.count - 1) % 2, 0)

        let entityTypes = stride(from: 0, to: lines.count - 1, by: 2)
            .filter { lines[$0] == "0" }
            .map { lines[$0 + 1] }
        let expectedLines = room.floorPolygon.count + room.walls.count + room.openings.count
        XCTAssertEqual(entityTypes.filter { $0 == "LINE" }.count, expectedLines)
        XCTAssertEqual(entityTypes.filter { $0 == "TEXT" }.count, room.walls.count * 2)
        XCTAssertTrue(dxf.contains("13' 1 1/2\""))  // 4 m wall

        // Wall A runs from (0,0) to (4,0) m = 157.48 in.
        XCTAssertTrue(dxf.contains("157.4803"))
        let metric = DXFWriter.write(room, measurements: m, units: .metric)
        XCTAssertTrue(metric.contains("4000.0000"))
    }

    /// Writes sample files when DXF_SAMPLE_DIR is set, for checking with an external DXF reader.
    func testWriteSampleFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["DXF_SAMPLE_DIR"] else { return }
        let room = sampleRoom()
        let m = MeasurementCalculator.measure(room)
        for units in UnitSystem.allCases {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("sample-\(units.rawValue).dxf")
            try DXFWriter.write(room, measurements: m, units: units).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
