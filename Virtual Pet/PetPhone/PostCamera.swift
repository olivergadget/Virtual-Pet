import Foundation
#if canImport(UIKit)
import AVFoundation
import SwiftUI
import UIKit

/// The camera behind the postcard composer.
///
/// Everything AVFoundation touches lives on a private queue inside ``CaptureRig``,
/// because configuring and starting a capture session blocks for long enough to stutter
/// the whole interface if it is done on the main thread. What comes back out is a photo.
@Observable
final class PostCamera {
    enum Status: Equatable {
        case idle
        case running
        /// Access was refused, or has been turned off in Settings since.
        case denied
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// The photo just taken. The composer takes it from here and clears it when done.
    var captured: UIImage?
    private(set) var isFrontFacing = false

    fileprivate let rig = CaptureRig()
    private var pump: Task<Void, Never>?
    /// Tells a photo which way up it should come out. Made once the session has a camera
    /// in it, because it has to be tied to that specific camera.
    private var rotation: AVCaptureDevice.RotationCoordinator?

    deinit {
        rig.teardown()
    }

    /// Asks for camera access the first time, then gets the session going. Safe to call
    /// again — coming back from the background lands here.
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }

        // The pump runs for as long as this camera object does. Stopping only stops the
        // session, because an `AsyncStream` cannot sensibly be iterated twice.
        if pump == nil {
            let events = rig.events
            pump = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    self.handle(event)
                }
            }
        }
        rig.start()
    }

    func stop() {
        rig.stop()
        status = .idle
    }

    func flip() {
        isFrontFacing.toggle()
        rotation = nil
        rig.flip()
    }

    func capture() {
        guard status == .running else { return }
        rig.capture(rotationAngle: rotation?.videoRotationAngleForHorizonLevelCapture ?? 0)
    }

    private func handle(_ event: CaptureRig.Event) {
        switch event {
        case .started:
            status = .running
            if let device = rig.device {
                rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            }

        case .photo(let image):
            captured = image

        case .failed(let reason):
            status = .failed(reason)
        }
    }
}

// MARK: - Session

/// The capture session and everything that has to be said to it on a background queue.
///
/// Unchecked: `input` is guarded by `lock`; `position` and `receiver` are only touched
/// from `queue`, which is where every one of these methods does its work.
private nonisolated final class CaptureRig: @unchecked Sendable {
    enum Event: Sendable {
        case started
        case photo(UIImage)
        case failed(String)
    }

    let session = AVCaptureSession()
    let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation
    private let queue = DispatchQueue(label: "PetPhone.camera")
    private let output = AVCapturePhotoOutput()
    private let lock = NSLock()

    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    /// Retained by hand: `capturePhoto(with:delegate:)` does not hold on to its delegate,
    /// and a delegate that has been released never reports anything back.
    private var receiver: PhotoReceiver?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = continuation
    }

    /// The camera currently feeding the session, so the preview can work out which way up
    /// it should be drawn.
    var device: AVCaptureDevice? {
        lock.lock()
        defer { lock.unlock() }
        return input?.device
    }

    func start() {
        queue.async { [self] in
            guard input != nil else {
                configure(for: position)
                return
            }
            if !session.isRunning { session.startRunning() }
            continuation.yield(.started)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Closes the event stream for good. Only called when the camera object goes away.
    func teardown() {
        stop()
        continuation.finish()
    }

    func flip() {
        queue.async { [self] in
            configure(for: position == .back ? .front : .back)
        }
    }

    func capture(rotationAngle: CGFloat) {
        queue.async { [self] in
            guard session.isRunning else {
                continuation.yield(.failed("The camera isn't running."))
                return
            }

            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }

            let receiver = PhotoReceiver { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .photo(let image):
                    self.continuation.yield(.photo(image))
                case .failed(let reason):
                    self.continuation.yield(.failed(reason))
                }
                // It has done its one job.
                self.queue.async { self.receiver = nil }
            }
            self.receiver = receiver
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: receiver)
        }
    }

    // MARK: Configuration

    private func configure(for wanted: AVCaptureDevice.Position) {
        guard let camera = Self.camera(at: wanted) else {
            continuation.yield(.failed("There's no camera on this device to take a postcard with."))
            return
        }
        guard let deviceInput = try? AVCaptureDeviceInput(device: camera) else {
            continuation.yield(.failed("The camera wouldn't open."))
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        lock.lock()
        let existing = input
        lock.unlock()
        if let existing { session.removeInput(existing) }

        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            continuation.yield(.failed("The camera wouldn't open."))
            return
        }
        session.addInput(deviceInput)

        lock.lock()
        input = deviceInput
        lock.unlock()
        position = wanted

        if session.outputs.isEmpty {
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                continuation.yield(.failed("The camera wouldn't open."))
                return
            }
            session.addOutput(output)
        }

        // The preview mirrors the front camera on its own. A selfie that then comes out
        // the other way round from what was on screen is a nasty little surprise, so the
        // photo is flipped to match.
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = wanted == .front
        }

        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        continuation.yield(.started)
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualWideCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }
}

/// The shutter's one-shot delegate.
private nonisolated final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate {
    enum Outcome: Sendable {
        case photo(UIImage)
        case failed(String)
    }

    private let finished: @Sendable (Outcome) -> Void

    init(finished: @escaping @Sendable (Outcome) -> Void) {
        self.finished = finished
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            finished(.failed("That photo didn't come out. Have another go."))
            return
        }
        finished(.photo(image))
    }
}

// MARK: - Preview

/// Hosts the session's preview layer, which is Core Animation rather than SwiftUI and so
/// needs a view of its own to live in.
struct CameraPreview: UIViewRepresentable {
    let camera: PostCamera

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.attach(session: camera.rig.session, device: camera.rig.device)
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        // The camera changes when it's flipped, and the rotation coordinator has to
        // follow whichever one is feeding the session now.
        view.attach(session: camera.rig.session, device: camera.rig.device)
    }
}

/// A view whose backing layer *is* the preview layer, which is the supported way to put
/// one on screen.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        // Guaranteed by `layerClass` above.
        layer as! AVCaptureVideoPreviewLayer
    }

    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var observation: NSKeyValueObservation?

    /// Idempotent: called again on every SwiftUI update, and does nothing unless the
    /// camera behind the preview has actually changed.
    func attach(session: AVCaptureSession, device: AVCaptureDevice?) {
        if previewLayer.session !== session {
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }

        guard let device, coordinator?.device !== device else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.coordinator = coordinator
        // Keeps the preview level as the phone is turned. Documented to be delivered on
        // the main queue, which is why assuming main-actor isolation is safe here.
        observation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            MainActor.assumeIsolated {
                guard let self,
                      let connection = self.previewLayer.connection,
                      connection.isVideoRotationAngleSupported(angle)
                else { return }
                connection.videoRotationAngle = angle
            }
        }
    }
}
#endif
