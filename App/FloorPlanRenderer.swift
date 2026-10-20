import RoomGeometry
import SwiftUI
import UIKit

/// Draws a dimensioned floor plan into any y-down Core Graphics context.
/// The on-screen plan and the PDF report share this code.
struct FloorPlanRenderer {
    struct Style {
        var wall: UIColor
        var highlight: UIColor
        var floor: UIColor
        var background: UIColor
        var text: UIColor
        var secondaryText: UIColor

        static let print = Style(
            wall: .black, highlight: .systemOrange, floor: UIColor(white: 0.94, alpha: 1),
            background: .white, text: .black, secondaryText: .darkGray
        )

        static func screen(_ scheme: ColorScheme) -> Style {
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            return Style(
                wall: UIColor.label.resolvedColor(with: traits),
                highlight: UIColor.systemOrange.resolvedColor(with: traits),
                floor: UIColor.secondarySystemFill.resolvedColor(with: traits),
                background: UIColor.systemBackground.resolvedColor(with: traits),
                text: UIColor.label.resolvedColor(with: traits),
                secondaryText: UIColor.secondaryLabel.resolvedColor(with: traits)
            )
        }
    }

    var room: Room
    var measurements: RoomMeasurements
    var units: UnitSystem
    var style: Style
    var highlightedWall: UUID?

    func draw(in ctx: CGContext, rect: CGRect) {
        guard let bounds = room.bounds else { return }
        let labelSpace = 34.0
        let t = PlanTransform.fit(bounds, width: rect.width, height: rect.height, padding: labelSpace)
        func point(_ p: Point2) -> CGPoint {
            let q = t.apply(p)
            return CGPoint(x: rect.minX + q.x, y: rect.minY + q.y)
        }

        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if room.floorPolygon.count >= 3 {
            ctx.beginPath()
            ctx.addLines(between: room.floorPolygon.map(point))
            ctx.closePath()
            ctx.setFillColor(style.floor.cgColor)
            ctx.fillPath()
        }

        ctx.setLineCap(.round)
        for wall in room.walls {
            ctx.setStrokeColor((wall.id == highlightedWall ? style.highlight : style.wall).cgColor)
            ctx.setLineWidth(4)
            ctx.strokeLineSegments(between: [point(wall.start), point(wall.end)])
        }

        // Openings: cut the wall line, then draw a thin colored marker in the gap.
        ctx.setLineCap(.butt)
        for opening in room.openings {
            let segment = [point(opening.start), point(opening.end)]
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setStrokeColor(style.background.cgColor)
            ctx.setLineWidth(6)
            ctx.strokeLineSegments(between: segment)

            ctx.setLineWidth(2)
            switch opening.kind {
            case .door:
                ctx.setStrokeColor(UIColor.systemBrown.cgColor)
            case .window:
                ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            case .opening:
                ctx.setStrokeColor(style.secondaryText.cgColor)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
            }
            ctx.strokeLineSegments(between: segment)
        }
        ctx.setLineDash(phase: 0, lengths: [])

        let offset = 14 / t.scale
        let center = room.center
        let dimensionFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let letterFont = UIFont.systemFont(ofSize: 12, weight: .bold)
        for wall in room.walls {
            guard let m = measurements.wall(wall.id) else { continue }
            let placement = PlanLayout.labelPlacement(for: wall, roomCenter: center, offset: offset)
            let marker = m.lengthIsOverridden ? "*" : ""
            drawText(Units.formatLength(m.length, units) + marker,
                     at: point(placement.dimensionAnchor), angle: placement.angle,
                     font: dimensionFont, color: style.text, in: ctx)
            drawText(m.label, at: point(placement.letterAnchor), angle: 0,
                     font: letterFont, color: style.secondaryText, in: ctx)
        }
    }

    private func drawText(_ text: String, at center: CGPoint, angle: Double, font: UIFont, color: UIColor, in ctx: CGContext) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        ctx.restoreGState()
    }
}

struct FloorPlanView: View {
    let room: Room
    let measurements: RoomMeasurements
    let units: UnitSystem
    var highlightedWall: UUID?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let renderer = FloorPlanRenderer(
            room: room, measurements: measurements, units: units,
            style: .screen(colorScheme), highlightedWall: highlightedWall
        )
        Canvas { context, size in
            context.withCGContext { cg in
                renderer.draw(in: cg, rect: CGRect(origin: .zero, size: size))
            }
        }
        .accessibilityLabel("Floor plan with \(room.walls.count) walls")
    }
}
