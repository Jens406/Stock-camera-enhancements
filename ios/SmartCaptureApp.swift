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
        let ruleContext = RuleContext(classification: classification, date: Date(), location: nil)
        let profile = ruleEngine.selectProfile(context: ruleContext,
                                               profiles: profileManager.loadProfiles())
        let enriched = metadataWriter.embedMetadata(imageData: data,
                                                    profile: profile,
                                                    context: ruleContext)
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
    private let classificationSizeThreshold = 200_000

    func classify(imageData: Data) -> Classification {
        guard imageData.count > 0 else { return .unknown }
        // Placeholder heuristic until a real ML-based classifier is integrated.
        return imageData.count < classificationSizeThreshold ? .receipt : .hiveInspection
    }
}

final class RuleEngine {
    private static func weekdays(from symbols: [String]) -> Set<Int> {
        let mapping: [String: Int] = [
            "Sun": 1,
            "Mon": 2,
            "Tue": 3,
            "Wed": 4,
            "Thu": 5,
            "Fri": 6,
            "Sat": 7
        ]
        return Set(symbols.compactMap { mapping[$0] })
    }

    private let rules: [Rule] = [
        Rule(
            id: "rule_receipts_workhours",
            classifier: .receipt,
            fromHour: 8,
            toHour: 18,
            weekdays: RuleEngine.weekdays(from: ["Mon", "Tue", "Wed", "Thu", "Fri"]),
            applyProfileId: "profile_receipts"
        )
    ]

    func selectProfile(context: RuleContext, profiles: [Profile]) -> Profile {
        guard !profiles.isEmpty else { return ProfileManager.fallbackProfile }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: context.date)
        let hour = calendar.component(.hour, from: context.date)
        let minute = calendar.component(.minute, from: context.date)
        let minuteOfDay = (hour * 60) + minute
        if let matched = rules.first(where: { rule in
            let fromMinute = rule.fromHour * 60
            let toMinute = rule.toHour * 60
            rule.classifier == context.classification &&
            rule.weekdays.contains(weekday) &&
            minuteOfDay >= fromMinute &&
            minuteOfDay < toMinute
        }), let profile = profiles.first(where: { $0.id == matched.applyProfileId }) {
            return profile
        }
        return profiles.first(where: { $0.id == "profile_hive" }) ?? profiles[0]
    }
}

final class ProfileManager {
    private let namespace = "https://smartcapture.app/xmp/1.0/"
    static let fallbackProfile = Profile(
        id: "profile_general",
        name: "General",
        libraryId: "general",
        xmpNamespace: "https://smartcapture.app/xmp/1.0/",
        xmp: [
            "DocumentType": "General",
            "WorkflowStage": "Raw",
            "Category": "General"
        ],
        exif: [
            "Artist": "User",
            "Software": "SmartCapture 1.0"
        ],
        shortcutIdentifier: "smartcapture_general_camera"
    )

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
        // Placeholder for XMP/EXIF embedding based on selected profile.
        _ = profile.id
        _ = context.classification
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
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let relativePath = library.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetDir = documents.appendingPathComponent(relativePath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            print("SmartCapture: failed to create directory: \(error)")
            return
        }
        let filename = "sc_\(UUID().uuidString).jpg"
        let fileURL = targetDir.appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            print("SmartCapture: failed to save image: \(error)")
        }
    }
}
