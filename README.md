# Smart Capture Profiles – Concept & Architecture
_Inspiration document for Apple and Google_

Author: Jens Sperens  
Date: 2026-04-19

---

## 1. Vision

Modern camera usage is no longer just “take a photo” – it’s “capture a document”, “log a receipt”, “record a field inspection”, “document an asset”, etc.

**Smart Capture Profiles** introduces a user-defined, rule-based capture system that:

- Lets users define **profiles** (Receipts, Documents, Hive Inspection, Field Ops, Personal Photos).
- Automatically:
  - **Classifies** captured or imported images.
  - **Applies a profile** (destination, metadata, workflow tags).
  - **Writes XMP/EXIF metadata** that travels with the image.
  - **Stores** the resulting file in a structured, user-defined library.
- Exposes this through:
  - A **simple camera UI** that feels like the native camera.
  - **Shortcuts/Intents** per profile for one-tap or voice-triggered capture.

The goal is to keep the user experience as simple as the stock camera while enabling a powerful, rule-based, metadata-rich pipeline behind the scenes.

---

## 2. Platform Constraints & Design Assumptions

### 2.1 iOS

iOS does **not** allow:

- Modifying EXIF/XMP **in-place** for images already in the Photos library.
- Changing the system camera’s save folder.

iOS **does** allow:

- Custom camera UIs.
- Saving images with metadata **before** writing to storage.
- Importing images from Photos and saving **new processed versions**.
- Shortcuts & Intents for automation.

### 2.2 Android

Android does **not** guarantee:

- Safe in-place EXIF/XMP modification for images managed by OEM gallery apps.

Android **does** allow:

- Custom camera UIs.
- Saving images with metadata.
- Reading from DCIM and creating processed copies.
- Intents, App Shortcuts, and automation integration.

### 2.3 Design Principle

> **Never mutate the system’s original file.**  
> Always create a **new, metadata-rich version** stored in a structured library.

---

## 3. High-Level Architecture

### 3.1 Core Components

1. **Profile Manager**  
   User-defined profiles containing:
   - Name, icon, color
   - Destination folder
   - XMP schema
   - EXIF fields
   - Classifier hints
   - Shortcut/Intent bindings

2. **Rule Engine**  
   Evaluates rules after capture or import.  
   Inputs: classifier result, time, location, device context.  
   Output: selected profile + overrides.

3. **Capture Module**  
   Custom camera UI mimicking native camera:
   - Shutter button
   - Tap-to-focus
   - Pinch-to-zoom
   - Fast startup

4. **Import & Processing Module**
   - Import from Photos/Gallery
   - Classify
   - Apply rules
   - Apply profile
   - Write metadata
   - Save processed copy

5. **Metadata Engine**
   - Writes EXIF
   - Writes XMP (custom namespaces)
   - Ensures metadata survives cloud sync

6. **Library Manager**  
   Structured storage in profile-based folders using a deterministic naming strategy (for example, profile/date/project). Originals remain untouched in system libraries.
