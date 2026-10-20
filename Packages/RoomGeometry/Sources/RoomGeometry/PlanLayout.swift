import Foundation

/// Maps plan meters to a drawing surface whose y axis points down (UIKit, PDF, SwiftUI).
public struct PlanTransform: Hashable, Sendable {
    /// Drawing points per meter.
    public var scale: Double
    public var originX: Double
    public var originY: Double

    public func apply(_ p: Point2) -> Point2 {
        Point2(x: originX + p.x * scale, y: originY - p.y * scale)
    }

    /// Fits `bounds` centered inside a `width` × `height` area with `padding` on every side.
    public static func fit(_ bounds: Bounds, width: Double, height: Double, padding: Double) -> PlanTransform {
        let availableW = max(1, width - 2 * padding)
        let availableH = max(1, height - 2 * padding)
        let scale = min(availableW / max(bounds.width, 0.01), availableH / max(bounds.height, 0.01))
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2
        return PlanTransform(
            scale: scale,
            originX: width / 2 - centerX * scale,
            originY: height / 2 + centerY * scale
        )
    }
}

public struct WallLabelPlacement: Hashable, Sendable {
    /// Where the dimension text is centered, in plan meters, outside the room.
    public var dimensionAnchor: Point2
    /// Where the wall letter is centered, in plan meters, inside the room.
    public var letterAnchor: Point2
    /// Text rotation in radians for a y-down drawing surface, kept between -π/2 and π/2
    /// so text never reads upside down.
    public var angle: Double
}

public enum PlanLayout {
    public static func labelPlacement(for wall: Wall, roomCenter: Point2, offset: Double) -> WallLabelPlacement {
        let direction = wall.end - wall.start
        let length = max(direction.length, 1e-9)
        var normal = Point2(x: -direction.y / length, y: direction.x / length)
        let mid = wall.midpoint
        // Point the normal away from the room.
        if (mid + normal - roomCenter).length < (mid - roomCenter).length {
            normal = normal * -1
        }
        // Plan y is up; drawing y is down, so the on-screen angle negates dy.
        var angle = atan2(-direction.y, direction.x)
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        return WallLabelPlacement(
            dimensionAnchor: mid + normal * offset,
            letterAnchor: mid - normal * offset,
            angle: angle
        )
    }
}
