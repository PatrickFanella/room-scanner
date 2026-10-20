import Foundation
import RoomGeometry
import RoomPlan
import simd

/// Converts RoomPlan output into the plain geometry model used for measuring and exporting.
enum RoomConverter {
    static func room(from captured: CapturedRoom) -> Room {
        let walls = captured.walls.map { surface in
            let (start, end) = endpoints(of: surface)
            return Wall(id: surface.identifier, start: start, end: end, height: Double(surface.dimensions.y))
        }

        let openings = captured.doors.map { opening($0, .door) }
            + captured.windows.map { opening($0, .window) }
            + captured.openings.map { opening($0, .opening) }

        return Room(walls: walls, openings: openings, floorPolygon: floorPolygon(captured, walls: walls))
    }

    /// A wall, door, or window is a rectangle centered on its transform, with its width
    /// along the local x axis.
    private static func endpoints(of surface: CapturedRoom.Surface) -> (Point2, Point2) {
        let center = surface.transform.columns.3
        let xAxis = surface.transform.columns.0
        let half = surface.dimensions.x / 2
        return (plan(center - xAxis * half), plan(center + xAxis * half))
    }

    private static func opening(_ surface: CapturedRoom.Surface, _ kind: OpeningKind) -> Opening {
        let (start, end) = endpoints(of: surface)
        return Opening(
            id: surface.identifier,
            kind: kind,
            wallID: surface.parentIdentifier,
            start: start,
            end: end,
            height: Double(surface.dimensions.y)
        )
    }

    /// Uses the largest scanned floor. RoomPlan documents `polygonCorners` as local to the
    /// surface; to guard against that assumption being wrong, both readings are computed and
    /// the one centered closer to the walls wins.
    private static func floorPolygon(_ captured: CapturedRoom, walls: [Wall]) -> [Point2] {
        let candidates = captured.floors.compactMap { floor -> [Point2]? in
            guard floor.polygonCorners.count >= 3 else { return nil }
            let local = floor.polygonCorners.map { plan(floor.transform * SIMD4<Float>($0, 1)) }
            let world = floor.polygonCorners.map { Point2(x: Double($0.x), y: Double(-$0.z)) }
            let wallCenter = Room(walls: walls, openings: [], floorPolygon: []).center
            let localCenter = Room(walls: [], openings: [], floorPolygon: local).center
            let worldCenter = Room(walls: [], openings: [], floorPolygon: world).center
            return localCenter.distance(to: wallCenter) <= worldCenter.distance(to: wallCenter) ? local : world
        }
        return candidates.max { Geometry.polygonArea($0) < Geometry.polygonArea($1) } ?? []
    }

    /// Top-down plan coordinates: x stays x, and y is world -z.
    private static func plan(_ v: SIMD4<Float>) -> Point2 {
        Point2(x: Double(v.x), y: Double(-v.z))
    }
}
