import RoomGeometry
import RoomPlan
import SwiftUI

struct ProjectDetailView: View {
    let projectID: UUID

    @Environment(ProjectStore.self) private var store
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var scanning = false
    @State private var editing = false
    @State private var confirmRescan = false
    @State private var selectedWall: UUID?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?

    var body: some View {
        if let project = store.project(projectID) {
            content(project)
                .navigationTitle(project.name)
                .navigationBarTitleDisplayMode(.inline)
                .fullScreenCover(isPresented: $scanning) {
                    ScanView { captured in store.attachScan(captured, to: projectID) }
                }
                .sheet(isPresented: $editing) {
                    EditMeasurementsView(project: project, units: units) { store.update($0) }
                }
                .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
                .alert("Export failed", isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(exportError ?? "")
                }
                .confirmationDialog("Replace the current scan?", isPresented: $confirmRescan, titleVisibility: .visible) {
                    Button("Rescan", role: .destructive) { scanning = true }
                } message: {
                    Text("The new scan replaces the floor plan, and measurements you entered by hand are cleared.")
                }
        } else {
            ContentUnavailableView("Project not found", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func content(_ project: Project) -> some View {
        if let room = project.room, let m = project.measurements {
            List {
                Section {
                    FloorPlanView(room: room, measurements: m, units: units, highlightedWall: selectedWall)
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                }

                Section("Room") {
                    row("Floor area", m.floorArea.map { Units.formatArea($0, units) } ?? "Not detected",
                        overridden: m.floorAreaIsOverridden)
                    row("Ceiling height", Units.formatLength(m.ceilingHeight, units), overridden: m.ceilingHeightIsOverridden)
                    row("Perimeter", Units.formatLength(m.perimeter, units))
                    row("Wall area, net", Units.formatArea(m.netWallArea, units))
                    row("Wall area, gross", Units.formatArea(m.grossWallArea, units))
                    row("Doors / windows / openings", "\(m.doorCount) / \(m.windowCount) / \(m.openingCount)")
                }

                Section {
                    ForEach(m.walls) { wall in
                        Button {
                            selectedWall = selectedWall == wall.id ? nil : wall.id
                        } label: {
                            WallRow(wall: wall, units: units, selected: selectedWall == wall.id)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Walls")
                } footer: {
                    Text("Net area subtracts doors, windows, and openings. * marks a value entered by hand.")
                }

                Section("Notes") {
                    TextField("Site conditions, materials, access…", text: Binding(
                        get: { project.notes },
                        set: { var p = project; p.notes = $0; store.update(p) }
                    ), axis: .vertical)
                    .lineLimit(3...10)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                    Menu {
                        Button("PDF report", systemImage: "doc.richtext") { export { try Exporter.pdf(project, measurements: m, units: units) } }
                        Button("DXF floor plan (CAD)", systemImage: "square.on.square.dashed") { export { try Exporter.dxf(project, measurements: m, units: units) } }
                        if let model = store.modelURL(for: project.id) {
                            Button("3D model (USDZ)", systemImage: "cube") { export { try Exporter.copy(model, as: "\(project.name).usdz") } }
                        }
                        Divider()
                        Button("Rescan room", systemImage: "camera.metering.matrix") { confirmRescan = true }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("No scan yet", systemImage: "camera.metering.matrix")
            } description: {
                if RoomCaptureSession.isSupported {
                    Text("Scan the room to get a floor plan, wall areas, and openings.")
                } else {
                    Text("Room scanning needs an iPhone or iPad with a LiDAR sensor.")
                }
            } actions: {
                Button("Scan room") { scanning = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!RoomCaptureSession.isSupported)
            }
        }
    }

    private func row(_ title: String, _ value: String, overridden: Bool = false) -> some View {
        LabeledContent(title, value: overridden ? value + " *" : value)
    }

    private func export(_ make: () throws -> URL) {
        do {
            shareItem = ShareItem(url: try make())
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct WallRow: View {
    let wall: WallMeasurement
    let units: UnitSystem
    let selected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(wall.label)
                .font(.headline)
                .frame(width: 32, alignment: .leading)
                .foregroundStyle(selected ? .orange : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Units.formatLength(wall.length, units))\(wall.lengthIsOverridden ? " *" : "") × \(Units.formatLength(wall.height, units))")
                    .monospacedDigit()
                if wall.openingCount > 0 {
                    Text("\(wall.openingCount) opening\(wall.openingCount == 1 ? "" : "s") · \(Units.formatArea(wall.openingArea, units))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Units.formatArea(wall.netArea, units))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
