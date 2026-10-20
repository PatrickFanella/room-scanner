import RoomGeometry
import SwiftUI

struct ProjectListView: View {
    @Environment(ProjectStore.self) private var store
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var path: [UUID] = []
    @State private var showingNewProject = false
    @State private var newProjectName = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.projects) { project in
                    NavigationLink(value: project.id) {
                        ProjectRow(project: project, units: units)
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.projects[$0].id }.forEach(store.delete)
                }
            }
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "No projects",
                        systemImage: "cube.transparent",
                        description: Text("Create a project, then scan a room to get its floor plan and measurements.")
                    )
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Units", selection: $units) {
                            ForEach(UnitSystem.allCases) { Text($0.displayName).tag($0) }
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newProjectName = ""
                        showingNewProject = true
                    } label: {
                        Label("New project", systemImage: "plus")
                    }
                }
            }
            .alert("New project", isPresented: $showingNewProject) {
                TextField("Kitchen, 14 Elm St", text: $newProjectName)
                Button("Create") { path.append(store.create(name: newProjectName).id) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Storage error", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name).font(.headline)
            HStack {
                if let area = project.measurements?.floorArea {
                    Text(Units.formatArea(area, units))
                } else if project.room == nil {
                    Text("Not scanned")
                }
                Spacer()
                Text(project.updatedAt, style: .date)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
