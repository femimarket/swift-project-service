//
//  ProjectService.swift
//  femi
//
//  Local file storage boundary. Every save and read goes through here;
//  nothing in this module touches the network or upload API. All XMP
//  metadata is written and read via the Adobe XMP Toolkit (xmp-toolkit-rs),
//  exposed through the XMPToolkit binary target. The toolkit's smart
//  handler picks the right packet location per format (JPEG APP1, PNG iTXt,
//  TIFF tag, MP4 `uuid` box, MOV `XMP_` atom, etc.).
//

import Foundation
import XMPToolkit

public enum ProjectService {
    /// App sandbox `Documents/`.
    public static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Embed XMP metadata into `data` (any format the toolkit recognizes)
    /// and write to `Documents/<file>`.
    ///
    /// - prompt → `dc:description` (Lang Alt) and `Iptc4xmpExt:AIPromptInformation`.
    /// - model  → `xmp:CreatorTool` and `Iptc4xmpExt:AISystemUsed`.
    /// - subject → `dc:subject` (Bag).
    ///
    /// When all three are nil the input bytes are written through unchanged.
    public static func saveFile(
        _ data: Data,
        named file: String,
        prompt: String? = nil,
        model: String? = nil,
        subject: [String]? = nil
    ) {
        let bytes: Data
        if prompt == nil && model == nil && subject == nil {
            bytes = data
        } else {
            bytes = embedXMP(data, file: file, prompt: prompt, model: model, subject: subject)
        }
        writeBytesToDocuments(bytes, named: file)
    }

    /// Set the like state by writing `xmp:Rating` (5 = liked, 0 = not).
    public static func like(_ file: String, _ liked: Bool) {
        let url = getUrl(for: file)
        let rating: Int32 = liked ? 5 : 0
        let result = url.path.withCString { psxmp_set_rating($0, rating) }
        precondition(result == 0, "psxmp_set_rating failed for \(file) with code \(result)")
    }

    /// List every file in the app's Documents folder.
    public static func getAllGenerations() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: nil
        )) ?? []
    }

    /// Replace the audio file in `Documents/`. Any existing audio files are
    /// deleted first, then `data` is written as `file`.
    public static func saveAudio(_ data: Data, named file: String) {
        for url in getAllGenerations() where isAudio(url) {
            try! FileManager.default.removeItem(at: url)
        }
        writeBytesToDocuments(data, named: file)
    }

    /// Returns the URL of the lone audio file in `Documents/`, if any.
    public static func getAudio() -> URL? {
        getAllGenerations().first(where: isAudio)
    }

    /// Read the prompt from `Iptc4xmpExt:AIPromptInformation` (falling back to
    /// `dc:description[x-default]`). Nil when absent.
    public static func getPrompt(_ file: String) -> String? {
        readString(at: getUrl(for: file), psxmp_read_prompt)
    }

    /// Read the model from `Iptc4xmpExt:AISystemUsed` (falling back to
    /// `xmp:CreatorTool`). Nil when absent.
    public static func getModel(_ file: String) -> String? {
        readString(at: getUrl(for: file), psxmp_read_model)
    }

    /// Read the subject keywords from `dc:subject`. Nil when absent.
    public static func getSubject(_ file: String) -> [String]? {
        let url = getUrl(for: file)
        let count = url.path.withCString { psxmp_read_subject_count($0) }
        guard count > 0 else { return nil }
        var result: [String] = []
        for i in 0..<count {
            if let s = readString(at: url, { p, b, l in psxmp_read_subject_at(p, i, b, l) }) {
                result.append(s)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Read the like state from `xmp:Rating` (`>= 1` = liked).
    public static func getLike(_ file: String) -> Bool {
        let rating = getUrl(for: file).path.withCString { psxmp_read_rating($0) }
        return (1...5).contains(rating)
    }

    public static func getUrl(for file: String) -> URL {
        documents.appendingPathComponent(URL(fileURLWithPath: file).lastPathComponent)
    }

    // MARK: - Operation arguments (in-memory, process-lifetime)

    /// Store the two filenames for the character-cast operation. Any prior
    /// pair is replaced. No validation is performed.
    public static func setCharacterCast(_ a: String, _ b: String) {
        characterCast = (a, b)
    }

    /// Return the previously-set character-cast pair, or `nil` if nothing
    /// has been set this process lifetime.
    public static func getCharacterCast() -> (String, String)? {
        characterCast
    }

    /// Drop the stored character-cast pair. Idempotent — no-op when nothing
    /// is set. After this call, `getCharacterCast()` returns `nil`.
    public static func clearCharacterCast() {
        characterCast = nil
    }

    nonisolated(unsafe) private static var characterCast: (String, String)?

    // MARK: - Internals

    private static func embedXMP(
        _ data: Data, file: String,
        prompt: String?, model: String?, subject: [String]?
    ) -> Data {
        let ext = URL(fileURLWithPath: file).pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try! data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = tempURL.path.withCString { pathPtr -> Int32 in
            withOptionalCString(prompt) { promptPtr in
                withOptionalCString(model) { modelPtr in
                    withCStringArray(subject ?? []) { arrPtr, count in
                        psxmp_embed(pathPtr, promptPtr, modelPtr, arrPtr, count)
                    }
                }
            }
        }
        precondition(result == 0, "psxmp_embed failed for \(file) with code \(result)")
        return try! Data(contentsOf: tempURL)
    }

    private static func writeBytesToDocuments(_ data: Data, named file: String) {
        let dest = getUrl(for: file)
        let ext = URL(fileURLWithPath: file).pathExtension
        var tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        if !ext.isEmpty { tempURL.appendPathExtension(ext) }
        try! data.write(to: tempURL)
        if FileManager.default.fileExists(atPath: dest.path) {
            _ = try! FileManager.default.replaceItemAt(dest, withItemAt: tempURL)
        } else {
            try! FileManager.default.moveItem(at: tempURL, to: dest)
        }
        precondition(
            FileManager.default.fileExists(atPath: dest.path),
            "saveFile: file not present after move at \(dest.path)"
        )
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "caf", "aiff", "aif", "flac", "ogg", "opus"
    ]

    private static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    private static func readString(
        at url: URL,
        _ reader: (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int32) -> Int32
    ) -> String? {
        var buf = [CChar](repeating: 0, count: 8192)
        let written = url.path.withCString { pathPtr in
            buf.withUnsafeMutableBufferPointer { bufPtr in
                reader(pathPtr, bufPtr.baseAddress, Int32(bufPtr.count))
            }
        }
        guard written > 0 else { return nil }
        let bytes = buf.prefix(Int(written)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func withOptionalCString<R>(
        _ s: String?, _ body: (UnsafePointer<CChar>?) -> R
    ) -> R {
        if let s {
            return s.withCString { body($0) }
        }
        return body(nil)
    }

    private static func withCStringArray<R>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?, Int32) -> R
    ) -> R {
        if strings.isEmpty { return body(nil, 0) }
        let dupped = strings.map { strdup($0)! }
        defer { dupped.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = dupped.map { UnsafePointer($0) }
        return pointers.withUnsafeMutableBufferPointer { buf in
            body(buf.baseAddress, Int32(strings.count))
        }
    }
}
