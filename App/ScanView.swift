import RoomPlan
import SwiftUI

/// Owns RoomPlan's capture view and reports its progress to SwiftUI.
///
/// RoomCaptureViewDelegate inherits NSCoding, hence the NSObject base and coder methods.
@MainActor
final class ScanSession: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum State {
        case scanning
        case processing
        case finished(CapturedRoom)
        case failed(String)
    }

    @Published private(set) var state: State = .scanning
    let captureView = RoomCaptureView(frame: .zero)
    private var isRunning = false

    override init() {
        super.init()
        captureView.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func encode(with coder: NSCoder) {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        state = .scanning
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// Ends capture; RoomPlan then processes the data and calls `didPresent`.
    func finish() {
        guard isRunning else { return }
        isRunning = false
        state = .processing
        captureView.captureSession.stop()
    }

    func cancel() {
        guard isRunning else { return }
        isRunning = false
        captureView.captureSession.stop()
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.state = .failed(error.localizedDescription)
            } else if processedResult.walls.isEmpty {
                self.state = .failed("No walls were detected. Try again and point the camera at each wall.")
            } else {
                self.state = .finished(processedResult)
            }
        }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let session: ScanSession

    func makeUIView(context: Context) -> RoomCaptureView { session.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct ScanView: View {
    let onSave: (CapturedRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = ScanSession()

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureContainer(session: session)
                .ignoresSafeArea()
            controls
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
        .onAppear { session.start() }
        .onDisappear { session.cancel() }
        .statusBarHidden()
    }

    @ViewBuilder
    private var controls: some View {
        switch session.state {
        case .scanning:
            VStack(spacing: 12) {
                Text("Walk slowly along the walls. Include every corner, door, and window.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Cancel", role: .cancel) {
                        session.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Done") { session.finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
        case .processing:
            ProgressView("Building the room model…")
        case .finished(let room):
            HStack {
                Button("Discard", role: .destructive) { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(room.walls.count) walls, \(room.doors.count) doors, \(room.windows.count) windows")
                    .font(.footnote)
                Spacer()
                Button("Save") {
                    onSave(room)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
