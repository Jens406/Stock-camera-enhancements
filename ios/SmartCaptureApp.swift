import SwiftUI
import AVFoundation
import Photos

@main
struct SmartCaptureApp: App {
    var body: some Scene {
        WindowGroup { CameraRootView() }
    }
}

struct CameraRootView: View {
    @StateObject private var vm = CameraViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: vm.session).ignoresSafeArea()
            VStack {
                Spacer()
                Button(action: { vm.capture() }) {
                    Circle().strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                }.padding(.bottom, 32)
            }
        }.onAppear { vm.configureSession() }
    }
}

final class CameraViewModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let processor = ImageProcessor()

    func configureSession() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else { session.commitConfiguration(); return }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func capture() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }
}

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        processor.processCapturedImage(data: data)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

final class ImageProcessor {
    private let classifier = ImageClassifier()
    private let ruleEngine = RuleEngine()
    private let profileManager = ProfileManager()
    private let metadataWriter = MetadataWriter()
    private let libraryManager = LibraryManager()

    func processCapturedImage(data: Data) {
        let classification = classifier.classify(imageData: data)
        let context = RuleContext(classification: classification, date: Date(), location: nil)
        let profile = ruleEngine.selectProfile(context: context,
                                               profiles: profileManager.loadProfiles())
        let enriched = metadataWriter.embedMetadata(imageData: data,
                                                    profile: profile,
                                                    context: context)
        libraryManager.save(imageData: enriched, profile: profile)
    }
}

enum Classification: String {
    case receipt
    case hiveInspection
    case unknown
}

struct RuleContext {
    let classification: Classification
    let date: Date
    let location: String?
}

struct LibraryDefinition {
    let id: String
    let path: String
}

struct Profile {
    let id: String
    let name: String
    let libraryId: String
    let xmpNamespace: String
    let xmp: [String: String]
    let exif: [String: String]
    let shortcutIdentifier: String
}

struct Rule {
    let id: String
    let classifier: Classification
    let fromHour: Int
    let toHour: Int
    let weekdays: Set<Int>
    let applyProfileId: String
}

final class ImageClassifier {
    func classify(imageData: Data) -> Classification {
        guard imageData.count > 0 else { return .unknown }
        return .receipt
    }
}

final class RuleEngine {
    private let rules: [Rule] = [
        Rule(
            id: "rule_receipts_workhours",
            classifier: .receipt,
            fromHour: 8,
            toHour: 18,
            weekdays: [2, 3, 4, 5, 6],
            applyProfileId: "profile_receipts"
        )
    ]

    func selectProfile(context: RuleContext, profiles: [Profile]) -> Profile {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: context.date)
        let hour = calendar.component(.hour, from: context.date)
        if let matched = rules.first(where: { rule in
            rule.classifier == context.classification &&
            rule.weekdays.contains(weekday) &&
            hour >= rule.fromHour &&
            hour <= rule.toHour
        }), let profile = profiles.first(where: { $0.id == matched.applyProfileId }) {
            return profile
        }
        return profiles.first(where: { $0.id == "profile_hive" }) ?? profiles[0]
    }
}

final class ProfileManager {
    private let namespace = "https://smartcapture.app/xmp/1.0/"

    func loadProfiles() -> [Profile] {
        [
            Profile(
                id: "profile_receipts",
                name: "Receipts",
                libraryId: "receipts",
                xmpNamespace: namespace,
                xmp: [
                    "DocumentType": "Receipt",
                    "WorkflowStage": "Raw",
                    "Category": "Finance",
                    "Vendor": "Auto",
                    "Confidence": "Auto"
                ],
                exif: [
                    "Artist": "User",
                    "Software": "SmartCapture 1.0"
                ],
                shortcutIdentifier: "smartcapture_receipt_camera"
            ),
            Profile(
                id: "profile_hive",
                name: "Hive Inspection",
                libraryId: "hive",
                xmpNamespace: namespace,
                xmp: [
                    "DocumentType": "HiveInspection",
                    "WorkflowStage": "Raw",
                    "Category": "Beekeeping"
                ],
                exif: [
                    "Artist": "User",
                    "Software": "SmartCapture 1.0"
                ],
                shortcutIdentifier: "smartcapture_hive_camera"
            )
        ]
    }
}

final class MetadataWriter {
    func embedMetadata(imageData: Data, profile: Profile, context: RuleContext) -> Data {
        _ = profile
        _ = context
        return imageData
    }
}

final class LibraryManager {
    private let libraries: [LibraryDefinition] = [
        LibraryDefinition(id: "receipts", path: "/SmartCapture/Receipts"),
        LibraryDefinition(id: "documents", path: "/SmartCapture/Documents"),
        LibraryDefinition(id: "hive", path: "/SmartCapture/Hive"),
        LibraryDefinition(id: "fieldops", path: "/SmartCapture/FieldOps"),
        LibraryDefinition(id: "general", path: "/SmartCapture/General")
    ]

    func save(imageData: Data, profile: Profile) {
        guard let library = libraries.first(where: { $0.id == profile.libraryId }) else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let relativePath = library.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetDir = documents.appendingPathComponent(relativePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let filename = "sc_\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = targetDir.appendingPathComponent(filename)
        try? imageData.write(to: fileURL, options: .atomic)
    }
}
