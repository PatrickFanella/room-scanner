import RoomGeometry
import UIKit

/// Writes shareable files into a fresh temporary folder.
enum Exporter {
    static func dxf(_ project: Project, measurements: RoomMeasurements, units: UnitSystem) throws -> URL {
        guard let room = project.room else { throw ExportError.noScan }
        let url = try outputURL("\(project.name) floor plan.dxf")
        try DXFWriter.write(room, measurements: measurements, units: units)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func copy(_ source: URL, as name: String) throws -> URL {
        let url = try outputURL(name)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    /// US Letter report: header, dimensioned plan, room summary, wall table, notes.
    static func pdf(_ project: Project, measurements m: RoomMeasurements, units: UnitSystem) throws -> URL {
        guard let room = project.room else { throw ExportError.noScan }
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: project.name]

        let data = UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            var writer = PageWriter(context: context, page: page, margin: margin)
            context.beginPage()

            writer.text(project.name, font: .systemFont(ofSize: 20, weight: .bold))
            writer.text("Scanned plan · \(Date().formatted(date: .long, time: .shortened)) · \(units.displayName)",
                        font: .systemFont(ofSize: 10), color: .darkGray)
            writer.space(10)

            let planRect = CGRect(x: margin, y: writer.y, width: page.width - 2 * margin, height: 380)
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.lightGray.cgColor)
            cg.setLineWidth(0.5)
            cg.stroke(planRect)
            FloorPlanRenderer(room: room, measurements: m, units: units, style: .print, highlightedWall: nil)
                .draw(in: cg, rect: planRect)
            writer.y = planRect.maxY + 16

            writer.heading("Room")
            writer.row(["Floor area", m.floorArea.map { Units.formatArea($0, units) } ?? "not detected",
                        "Ceiling height", Units.formatLength(m.ceilingHeight, units)],
                       marks: [m.floorAreaIsOverridden, m.ceilingHeightIsOverridden])
            writer.row(["Perimeter", Units.formatLength(m.perimeter, units),
                        "Doors / windows / openings", "\(m.doorCount) / \(m.windowCount) / \(m.openingCount)"])
            writer.row(["Wall area, net", Units.formatArea(m.netWallArea, units),
                        "Wall area, gross", Units.formatArea(m.grossWallArea, units)])
            writer.space(8)

            writer.heading("Walls")
            writer.row(["Wall", "Length", "Height", "Openings", "Net area"], bold: true, columns: PageWriter.wallColumns)
            for wall in m.walls {
                writer.row([wall.label,
                            Units.formatLength(wall.length, units) + (wall.lengthIsOverridden ? " *" : ""),
                            Units.formatLength(wall.height, units),
                            wall.openingCount == 0 ? "–" : "\(wall.openingCount) · \(Units.formatArea(wall.openingArea, units))",
                            Units.formatArea(wall.netArea, units)],
                           columns: PageWriter.wallColumns)
            }

            if !project.notes.isEmpty {
                writer.space(8)
                writer.heading("Notes")
                writer.paragraph(project.notes)
            }

            writer.space(12)
            writer.paragraph("Measured with a LiDAR room scan. * marks values entered by hand. "
                             + "Net wall area subtracts doors, windows, and openings. "
                             + "Verify critical dimensions on site before ordering or cutting.",
                             font: .systemFont(ofSize: 8), color: .darkGray)
        }

        let url = try outputURL("\(project.name) floor plan.pdf")
        try data.write(to: url)
        return url
    }

    private static func outputURL(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return dir.appending(path: safe)
    }

    enum ExportError: LocalizedError {
        case noScan
        var errorDescription: String? { "This project has no scan to export." }
    }
}

/// Lays out text top to bottom and starts a new page when the current one is full.
private struct PageWriter {
    static let wallColumns: [CGFloat] = [0, 50, 160, 260, 420]
    static let summaryColumns: [CGFloat] = [0, 120, 266, 420]

    let context: UIGraphicsPDFRendererContext
    let page: CGRect
    let margin: CGFloat
    var y: CGFloat

    init(context: UIGraphicsPDFRendererContext, page: CGRect, margin: CGFloat) {
        self.context = context
        self.page = page
        self.margin = margin
        self.y = margin
    }

    private var width: CGFloat { page.width - 2 * margin }

    mutating func space(_ amount: CGFloat) { y += amount }

    mutating func heading(_ text: String) {
        ensureRoom(for: 40)
        self.text(text, font: .systemFont(ofSize: 13, weight: .semibold))
        space(2)
    }

    mutating func text(_ string: String, font: UIFont, color: UIColor = .black) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        ensureRoom(for: attributed.size().height)
        attributed.draw(at: CGPoint(x: margin, y: y))
        y += attributed.size().height + 2
    }

    mutating func paragraph(_ string: String, font: UIFont = .systemFont(ofSize: 10), color: UIColor = .black) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], context: nil)
        ensureRoom(for: bounds.height)
        attributed.draw(with: CGRect(x: margin, y: y, width: width, height: bounds.height),
                        options: [.usesLineFragmentOrigin], context: nil)
        y += ceil(bounds.height) + 2
    }

    /// Draws cells at fixed column offsets. Odd-indexed cells in the summary layout are values.
    mutating func row(_ cells: [String], bold: Bool = false, marks: [Bool] = [], columns: [CGFloat] = summaryColumns) {
        let height: CGFloat = 15
        ensureRoom(for: height)
        for (index, cell) in cells.enumerated() where index < columns.count {
            let isMarkedValue = index % 2 == 1 && marks.indices.contains(index / 2) && marks[index / 2]
            let font: UIFont = bold ? .systemFont(ofSize: 10, weight: .semibold) : .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            NSAttributedString(string: cell + (isMarkedValue ? " *" : ""), attributes: [.font: font])
                .draw(at: CGPoint(x: margin + columns[index], y: y))
        }
        y += height
    }

    private mutating func ensureRoom(for height: CGFloat) {
        if y + height > page.height - margin {
            context.beginPage()
            y = margin
        }
    }
}
