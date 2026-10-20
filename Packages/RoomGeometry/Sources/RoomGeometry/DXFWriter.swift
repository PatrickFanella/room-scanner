import Foundation

/// Writes a 2D floor plan as an ASCII DXF (AutoCAD R12) file.
///
/// Imperial drawings use inches and metric drawings use millimeters, matching
/// what most CAD users expect. Layers: WALLS, DOORS, WINDOWS, OPENINGS, FLOOR,
/// DIMENSIONS, LABELS.
public enum DXFWriter {
    public static func write(_ room: Room, measurements: RoomMeasurements, units: UnitSystem) -> String {
        let scale = units == .imperial ? 1 / Units.metersPerInch : 1000
        let textHeight = units == .imperial ? 4.0 : 100.0  // 4 in or 100 mm
        let center = room.center
        var out = Output()

        out.pair(0, "SECTION"); out.pair(2, "HEADER")
        out.pair(9, "$ACADVER"); out.pair(1, "AC1009")
        out.pair(9, "$INSUNITS"); out.pair(70, units == .imperial ? "1" : "4")
        out.pair(0, "ENDSEC")

        out.pair(0, "SECTION"); out.pair(2, "ENTITIES")

        if room.floorPolygon.count >= 3 {
            for i in room.floorPolygon.indices {
                let a = room.floorPolygon[i]
                let b = room.floorPolygon[(i + 1) % room.floorPolygon.count]
                out.line(a * scale, b * scale, layer: "FLOOR")
            }
        }

        for wall in room.walls {
            out.line(wall.start * scale, wall.end * scale, layer: "WALLS")
            guard let m = measurements.wall(wall.id) else { continue }
            let placement = PlanLayout.labelPlacement(for: wall, roomCenter: center, offset: 0.25)
            // DXF y points up, so flip the y-down angle back.
            let degrees = -placement.angle * 180 / .pi
            out.text(Units.formatLength(m.length, units), at: placement.dimensionAnchor * scale,
                     height: textHeight, rotation: degrees, layer: "DIMENSIONS")
            out.text(m.label, at: placement.letterAnchor * scale,
                     height: textHeight * 1.5, rotation: 0, layer: "LABELS")
        }

        for opening in room.openings {
            let layer: String
            switch opening.kind {
            case .door: layer = "DOORS"
            case .window: layer = "WINDOWS"
            case .opening: layer = "OPENINGS"
            }
            out.line(opening.start * scale, opening.end * scale, layer: layer)
        }

        out.pair(0, "ENDSEC")
        out.pair(0, "EOF")
        return out.text
    }

    private struct Output {
        var text = ""

        mutating func pair(_ code: Int, _ value: String) {
            text += "\(code)\n\(value)\n"
        }

        mutating func number(_ code: Int, _ value: Double) {
            pair(code, String(format: "%.4f", value))
        }

        mutating func line(_ a: Point2, _ b: Point2, layer: String) {
            pair(0, "LINE"); pair(8, layer)
            number(10, a.x); number(20, a.y); number(30, 0)
            number(11, b.x); number(21, b.y); number(31, 0)
        }

        mutating func text(_ value: String, at p: Point2, height: Double, rotation: Double, layer: String) {
            // Center the text on `p`: horizontal justification 1 (center), vertical 2 (middle).
            pair(0, "TEXT"); pair(8, layer)
            number(10, p.x); number(20, p.y); number(30, 0)
            number(40, height)
            pair(1, value)
            number(50, rotation)
            pair(72, "1")
            number(11, p.x); number(21, p.y); number(31, 0)
            pair(73, "2")
        }
    }
}
