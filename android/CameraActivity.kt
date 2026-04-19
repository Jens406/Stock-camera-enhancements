package com.smartcapture.app

import android.content.Context
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File
import java.util.Calendar
import java.util.Date

class CameraActivity : AppCompatActivity() {

    private lateinit var controller: LifecycleCameraController
    private val processor = ImageProcessor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_camera)

        val preview: PreviewView = findViewById(R.id.previewView)
        controller = LifecycleCameraController(this)
        controller.bindToLifecycle(this)
        controller.cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        preview.controller = controller

        findViewById<android.view.View>(R.id.shutterButton).setOnClickListener { capture() }
    }

    private fun capture() {
        val file = createTempFile("sc_", ".jpg", cacheDir)
        val opts = ImageCapture.OutputFileOptions.Builder(file).build()

        controller.takePicture(
            opts,
            ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                    val bytes = file.readBytes()
                    processor.processCapturedImage(bytes, this@CameraActivity)
                    file.delete()
                }

                override fun onError(exc: ImageCaptureException) {}
            }
        )
    }
}

class ImageProcessor {
    private val classifier = ImageClassifier()
    private val ruleEngine = RuleEngine()
    private val profileManager = ProfileManager()
    private val metadataWriter = MetadataWriter()
    private val libraryManager = LibraryManager()

    fun processCapturedImage(data: ByteArray, ctx: Context) {
        val classification = classifier.classify(data)
        val context = RuleContext(classification, Date(), null)
        val profile = ruleEngine.selectProfile(context, profileManager.loadProfiles(ctx))
        val enriched = metadataWriter.embedMetadata(data, profile, context)
        libraryManager.save(enriched, profile, ctx)
    }
}

enum class Classification {
    receipt, hiveInspection, unknown
}

data class RuleContext(
    val classification: Classification,
    val date: Date,
    val location: String?
)

data class Profile(
    val id: String,
    val name: String,
    val libraryId: String,
    val xmpNamespace: String,
    val xmp: Map<String, String>,
    val exif: Map<String, String>,
    val shortcutIdentifier: String
)

data class Rule(
    val id: String,
    val classifier: Classification,
    val fromHour: Int,
    val toHour: Int,
    val daysOfWeek: Set<Int>,
    val applyProfileId: String
)

data class LibraryDefinition(
    val id: String,
    val path: String
)

class ImageClassifier {
    fun classify(data: ByteArray): Classification {
        if (data.isEmpty()) return Classification.unknown
        return if (data.size < 200_000) Classification.receipt else Classification.hiveInspection
    }
}

class RuleEngine {
    private val rules = listOf(
        Rule(
            id = "rule_receipts_workhours",
            classifier = Classification.receipt,
            fromHour = 8,
            toHour = 18,
            daysOfWeek = setOf(
                Calendar.MONDAY,
                Calendar.TUESDAY,
                Calendar.WEDNESDAY,
                Calendar.THURSDAY,
                Calendar.FRIDAY
            ),
            applyProfileId = "profile_receipts"
        )
    )

    fun selectProfile(context: RuleContext, profiles: List<Profile>): Profile {
        val calendar = Calendar.getInstance().apply { time = context.date }
        val day = calendar.get(Calendar.DAY_OF_WEEK)
        val hour = calendar.get(Calendar.HOUR_OF_DAY)
        val minute = calendar.get(Calendar.MINUTE)
        val minuteOfDay = (hour * 60) + minute

        val matchedRule = rules.firstOrNull {
            val fromMinute = it.fromHour * 60
            val toMinute = it.toHour * 60
            it.classifier == context.classification &&
                day in it.daysOfWeek &&
                minuteOfDay >= fromMinute &&
                minuteOfDay <= toMinute
        }

        return when {
            matchedRule != null -> profiles.firstOrNull { it.id == matchedRule.applyProfileId }
            else -> profiles.firstOrNull { it.id == "profile_hive" }
        } ?: profiles.first()
    }
}

class ProfileManager {
    fun loadProfiles(@Suppress("UNUSED_PARAMETER") ctx: Context): List<Profile> {
        val namespace = "https://smartcapture.app/xmp/1.0/"
        return listOf(
            Profile(
                id = "profile_receipts",
                name = "Receipts",
                libraryId = "receipts",
                xmpNamespace = namespace,
                xmp = mapOf(
                    "DocumentType" to "Receipt",
                    "WorkflowStage" to "Raw",
                    "Category" to "Finance",
                    "Vendor" to "Auto",
                    "Confidence" to "Auto"
                ),
                exif = mapOf(
                    "Artist" to "User",
                    "Software" to "SmartCapture 1.0"
                ),
                shortcutIdentifier = "smartcapture_receipt_camera"
            ),
            Profile(
                id = "profile_hive",
                name = "Hive Inspection",
                libraryId = "hive",
                xmpNamespace = namespace,
                xmp = mapOf(
                    "DocumentType" to "HiveInspection",
                    "WorkflowStage" to "Raw",
                    "Category" to "Beekeeping"
                ),
                exif = mapOf(
                    "Artist" to "User",
                    "Software" to "SmartCapture 1.0"
                ),
                shortcutIdentifier = "smartcapture_hive_camera"
            )
        )
    }
}

class MetadataWriter {
    fun embedMetadata(
        data: ByteArray,
        @Suppress("UNUSED_PARAMETER") profile: Profile,
        @Suppress("UNUSED_PARAMETER") context: RuleContext
    ): ByteArray {
        // Placeholder for XMP/EXIF embedding based on selected profile.
        return data
    }
}

class LibraryManager {
    private val libraries = listOf(
        LibraryDefinition("receipts", "/SmartCapture/Receipts"),
        LibraryDefinition("documents", "/SmartCapture/Documents"),
        LibraryDefinition("hive", "/SmartCapture/Hive"),
        LibraryDefinition("fieldops", "/SmartCapture/FieldOps"),
        LibraryDefinition("general", "/SmartCapture/General")
    )

    fun save(data: ByteArray, profile: Profile, ctx: Context) {
        val lib = libraries.firstOrNull { it.id == profile.libraryId } ?: return
        val root = File(ctx.filesDir, "SmartCapture")
        val leaf = lib.path.substringAfter("/SmartCapture/").trim('/')
        val targetDir = File(root, leaf)
        if (!targetDir.exists()) targetDir.mkdirs()
        val out = File(targetDir, "sc_${System.currentTimeMillis()}.jpg")
        out.writeBytes(data)
    }
}
