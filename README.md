# ProjectService

## Overview
`ProjectService` is an iOS Swift package that provides a secure, local file storage boundary with integrated XMP metadata management. It enables embedding and reading AI-related metadata (prompts, models, subjects, and ratings) directly into media files (images, videos, and audio) using Adobe's XMP Toolkit via a Rust FFI shim. The package isolates all file I/O to the app's `Documents` directory, ensuring network independence and sandbox compliance.

## Features
- **Local File Storage**: Atomic writes and reads within the app's `Documents` directory.
- **XMP Metadata Embedding & Reading**: Supports images (PNG, JPEG) and video (MP4) via Adobe's smart handler.
- **Like/Unlike State**: Manages `xmp:Rating` (0 = not liked, 5 = liked).
- **Audio Management**: Enforces a single-audio-file constraint with automatic cleanup.
- **In-Memory Operation Context**: Process-scoped state for cross-step workflows (`characterCast`, `imageEdit`).
- **Path Sanitization**: Strips path traversal attempts to guarantee files remain in `Documents/`.

## Architecture & Key Files
| Path | Description |
|------|-------------|
| `Package.swift` | SPM manifest. Targets iOS 14+, Swift 6 mode, and defines the `ProjectService` library. |
| `Sources/ProjectService/ProjectService.swift` | Swift API layer. Handles file I/O, FFI bridging, path sanitization, and business logic. |
| `rust-xmp/src/lib.rs` | Rust FFI shim exposing C ABI functions (`psxmp_*`) for XMP read/write operations using `xmp-toolkit-rs`. |
| `artifacts/XMPToolkit.xcframework` | Pre-built binary dependency wrapping Adobe's XMP Toolkit. Required for building. |
| `Tests/ProjectServiceTests/ProjectServiceTests.swift` | Comprehensive test suite covering all public APIs, format support, and edge cases. |

## Installation & Build
- **Requirements**: Swift 6.3+, Xcode 15+, iOS 14+ deployment target.
- **Prerequisites**: Ensure `artifacts/XMPToolkit.xcframework` is present in the repository root.
- **Build**:
  ```bash
  swift build
  ```
- **Run Tests**:
  ```bash
  swift test
  ```
- **Integration**: Add as a dependency in your Xcode project or via SPM URL. Import `ProjectService` in Swift files.

## Usage
### Saving Files with Metadata
```swift
let imageData: Data = ...
ProjectService.saveFile(
    imageData,
    named: "generated.png",
    prompt: "A cyberpunk city at sunset",
    model: "stable-diffusion-xl",
    subject: ["city", "sunset", "cyberpunk"]
)
```
If no metadata is provided, the input bytes are written through unchanged.

### Reading Metadata
```swift
let prompt = ProjectService.getPrompt("generated.png")
let model = ProjectService.getModel("generated.png")
let subjects = ProjectService.getSubject("generated.png")
let isLiked = ProjectService.getLike("generated.png")
```

### Liking / Unliking
```swift
ProjectService.like("generated.png", true)  // Sets xmp:Rating to 5
ProjectService.like("generated.png", false) // Sets xmp:Rating to 0
```

### Audio Management
```swift
ProjectService.saveAudio(audioData, named: "voiceover.m4a")
if let audioURL = ProjectService.getAudio() {
    // Play or process audioURL
}
```
*Note: Saving a new audio file automatically deletes any existing audio file in `Documents/`.*

### In-Memory Operation Context
```swift
ProjectService.setCharacterCast("hero.png", "villain.png")
let castPair = ProjectService.getCharacterCast() // ("hero.png", "villain.png")
ProjectService.clearCharacterCast()              // Resets to nil
```

### Listing Files
```swift
let allFiles: [URL] = ProjectService.getAllGenerations()
```

## XMP Metadata Mapping
The Rust FFI layer maps Swift parameters to standardized XMP namespaces:

| Swift Parameter | XMP Namespace & Property |
|-----------------|--------------------------|
| `prompt`        | `dc:description` (Lang Alt, `x-default`) + `Iptc4xmpExt:AIPromptInformation` |
| `model`         | `xmp:CreatorTool` + `Iptc4xmpExt:AISystemUsed` |
| `subject`       | `dc:subject` (Bag/Array) |
| `liked` (rating)| `xmp:Rating` (0 = unrated/unliked, 5 = liked) |

## Testing
The project uses the Swift Testing framework with serialized suite execution to prevent race conditions on the shared `Documents` directory:
```swift
@Suite("ProjectService", .serialized)
struct ProjectServiceTests { ... }
```
Tests cover:
- Plain file passthrough
- PNG and MP4 metadata embedding/round-tripping
- Rating state transitions
- Audio file mutual exclusion
- In-memory state lifecycle
- Path traversal protection (`../../../etc/passwd` → `passwd`)

## Important Conventions & Notes
- **Atomic Writes**: All file saves use temporary files in the system temp directory, followed by `replaceItemAt` or `moveItem` to prevent corruption during crashes or interruptions.
- **Path Sanitization**: `ProjectService.getUrl(for:)` uses `URL(fileURLWithPath: file).lastPathComponent` to strip directory traversal and ensure all files land strictly in `Documents/`.
- **Process-Scoped State**: `characterCast` and `imageEdit` are stored in `nonisolated(unsafe) static var` properties. They persist only for the lifetime of the process and must be explicitly cleared via `clearCharacterCast()` or `clearImageEdit()`.
- **XMP Smart Handler**: The underlying Rust layer uses `OpenFileOptions.default().use_smart_handler()`, which automatically routes metadata to the correct container format (JPEG APP1, PNG iTXt, TIFF tag, MP4 `uuid` box, etc.).
- **Error Handling**: FFI functions return negative integers on failure. The Swift layer uses `precondition` for critical failures during development/testing; production integrations should handle potential crashes or add error propagation as needed.
- **Swift 6 Strict Concurrency**: The package targets Swift 6 language mode. The `nonisolated(unsafe)` static variables bypass actor isolation intentionally for simple process-lifetime storage, but should be avoided in highly concurrent production code without proper synchronization.