# ProjectService

Local file-storage boundary for an iOS app. Saves and reads files in the app's `Documents/` directory, embeds XMP metadata into images (prompt, model, like state), and manages a single audio file as an exclusive slot.

Every save and read in the host app goes through this module. Nothing here touches the network.

## Requirements

- iOS 14+
- Swift 6 / Xcode 16+

## Install

Swift Package Manager:

```swift
.package(url: "https://your-host/ProjectService.git", from: "1.0.0")
```

Then add `"ProjectService"` as a dependency of any target that needs it.

## API

```swift
import ProjectService

// Save an image, embedding prompt, model and/or keywords into the XMP block.
ProjectService.saveFile(imageData, named: "out.png",
                        prompt: "a fox", model: "dalle-3",
                        subject: ["fox", "wildlife"])

// Toggle the "liked" flag (IPTC StarRating: 5 / 0).
ProjectService.like("out.png", true)

// Read what was embedded.
ProjectService.getPrompt("out.png")    // "a fox"
ProjectService.getModel("out.png")     // "dalle-3"
ProjectService.getSubject("out.png")   // ["fox", "wildlife"]
ProjectService.getLike("out.png")      // true

// Resolve a name to a URL (handy for image views, share sheets, etc.).
let url = ProjectService.getUrl(for: "out.png")

// List everything in Documents/.
ProjectService.getAllGenerations()    // [URL]

// Audio is a single-slot invariant: writing always deletes any prior audio.
ProjectService.saveAudio(bytes, named: "voice.m4a")
ProjectService.getAudio()             // URL? — the lone audio file, if any
```

## Storage model

- Files land directly in the app's sandboxed `Documents/` directory. No subdirectories.
- File names are taken as-is (the last path component) — path traversal is stripped.
- Images: optional prompt/model metadata is embedded in XMP. The bytes on disk are re-encoded when metadata is added; passed through unchanged when both `prompt` and `model` are nil.
- Audio: at most one audio file exists in `Documents/` at a time. `saveAudio` deletes every existing audio file (by extension whitelist: `mp3, m4a, wav, aac, caf, aiff, aif, flac, ogg, opus`) before writing the new one.

## XMP fields written

| Source | XMP fields written on disk |
|---|---|
| `prompt` | `dc:description` (Lang Alt) and `Iptc4xmpExt:AIPromptInformation` |
| `model` | `xmp:CreatorTool` and `Iptc4xmpExt:AISystemUsed` |
| `subject` | `dc:subject` (Bag of strings, via IPTC Keywords) |
| `liked` | `xmp:Rating` (via IPTC StarRating: 5 = liked, 0 = not) |

The duplication is intentional: the `dc:`/`xmp:` fields are universally recognized by XMP readers (Photoshop, exiftool, Finder previews); the `Iptc4xmpExt:AI*` fields are the IPTC-standard locations for AI-generated content metadata. Embedding both means broad compatibility plus AI-content provenance in the correct place.

`saveFile` does two ImageIO passes when embedding metadata: pass 1 writes the structured standard fields via the high-level `kCGImageProperty*` keys (necessary because `dc:description` requires a Lang Alt structure); pass 2 merges the custom `Iptc4xmpExt:` fields into the existing XMP block via `CGImageDestinationCopyImageSource`.

## Testing

Run tests through Xcode or `xcodebuild` against an iOS Simulator:

```sh
xcodebuild test -scheme ProjectService \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`swift test` from the command line won't work — the package is iOS-only.

Tests use unique per-instance filename prefixes (`psvc-test-<uuid>-...`) to avoid clobbering existing files and to keep the suite re-runnable.

## Known limitations

- **No concurrency control.** Overlapping calls to `saveFile`, `like`, or `saveAudio` for the same file (or to `saveAudio` from two threads at once) can race the temp-file → replace dance. Currently deferred — the public API stays synchronous.
- **Crashes on rare I/O failures.** Disk-full, sandbox revocation, file vanishing mid-flight, etc. all terminate the process via `try!` / `precondition` rather than throwing. Intentional: simple API, fail loudly on device misbehavior.
- **Type name.** The enum is still called `ProjectService` for historical reasons even though it no longer has any project concept; it's just a flat file store on `Documents/`.
