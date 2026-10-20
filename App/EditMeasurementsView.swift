import RoomGeometry
import SwiftUI

/// Lets the user replace scanned values with tape-measured ones.
/// An empty field means "use the scanned value".
struct EditMeasurementsView: View {
    let project: Project
    let units: UnitSystem
    let onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ceiling = ""
    @State private var floorArea = ""
    @State private var wallLengths: [UUID: String] = [:]
    @State private var invalidField: String?

    private var scanned: RoomMeasurements? {
        project.room.map { MeasurementCalculator.measure($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let scanned {
                    Section {
                        field("Ceiling height", text: $ceiling, scanned: Units.formatLength(scanned.ceilingHeight, units))
                        field("Floor area", text: $floorArea,
                              scanned: scanned.floorArea.map { Units.formatArea($0, units) } ?? "not detected")
                    } footer: {
                        Text(units == .imperial
                             ? "Enter lengths like 12' 3 1/2\" or 12.5 (feet). Leave a field empty to use the scan."
                             : "Enter lengths like 3.75, 375 cm or 3750 mm. Leave a field empty to use the scan.")
                    }

                    Section("Wall lengths") {
                        ForEach(scanned.walls) { wall in
                            field("Wall \(wall.label)", text: binding(for: wall.id),
                                  scanned: Units.formatLength(wall.length, units))
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear all", role: .destructive) {
                        ceiling = ""
                        floorArea = ""
                        wallLengths = [:]
                    }
                }
            }
            .alert("Check \(invalidField ?? "")", isPresented: Binding(
                get: { invalidField != nil },
                set: { if !$0 { invalidField = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That value could not be read as a positive measurement.")
            }
            .onAppear(perform: loadCurrentValues)
        }
    }

    private func field(_ title: String, text: Binding<String>, scanned: String) -> some View {
        LabeledContent(title) {
            TextField("Scan: \(scanned)", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(get: { wallLengths[id] ?? "" }, set: { wallLengths[id] = $0 })
    }

    private func loadCurrentValues() {
        let o = project.overrides
        ceiling = o.ceilingHeight.map { Units.formatLength($0, units) } ?? ""
        floorArea = o.floorArea.map { Units.formatArea($0, units) } ?? ""
        for wall in project.room?.walls ?? [] {
            if let length = o.wallLength(for: wall.id) {
                wallLengths[wall.id] = Units.formatLength(length, units)
            }
        }
    }

    private func save() {
        var overrides = MeasurementOverrides()
        guard let ceilingValue = parse(ceiling, name: "ceiling height", Units.parseLength),
              let floorValue = parse(floorArea, name: "floor area", Units.parseArea) else { return }
        overrides.ceilingHeight = ceilingValue
        overrides.floorArea = floorValue

        for (index, wall) in (project.room?.walls ?? []).enumerated() {
            let name = "wall \(MeasurementCalculator.wallLabel(index))"
            guard let value = parse(wallLengths[wall.id] ?? "", name: name, Units.parseLength) else { return }
            overrides.setWallLength(value, for: wall.id)
        }

        var updated = project
        updated.overrides = overrides
        onSave(updated)
        dismiss()
    }

    /// Returns `.some(nil)` for an empty field, `.some(value)` when valid, and `nil` (after
    /// flagging the field) when the text can't be parsed.
    private func parse(_ text: String, name: String, _ parser: (String, UnitSystem) -> Double?) -> Double?? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .some(nil) }
        guard let value = parser(text, units) else {
            invalidField = name
            return nil
        }
        return .some(value)
    }
}
