//
//  ProjectService.swift
//  femi
//
//  Local file storage boundary. Every save and read goes through here;
//  nothing in this module touches the network or upload API.
//

import Foundation
import ImageIO

public enum ProjectService {
    /// App sandbox `Documents/`.
    public static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Embed `prompt` as IPTC Caption/Abstract (XMP `dc:description`) and
    /// `model` as TIFF Software (XMP `xmp:CreatorTool`), then write to
    /// `Documents/<file>`. When both are nil the input bytes are written
    /// through unchanged.
    public static func saveFile(
        _ data: Data,
        named file: String,
        prompt: String? = nil,
        model: String? = nil
    ) {
        let out: Data
        if prompt == nil && model == nil {
            out = data
        } else {
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let type = CGImageSourceGetType(source)!

            var properties: [CFString: Any] = [:]
            if let prompt {
                properties[kCGImagePropertyIPTCDictionary] = [
                    kCGImagePropertyIPTCCaptionAbstract: prompt
                ] as [CFString: Any]
            }
            if let model {
                properties[kCGImagePropertyTIFFDictionary] = [
                    kCGImagePropertyTIFFSoftware: model
                ] as [CFString: Any]
            }

            let buffer = NSMutableData()
            let cgDest = CGImageDestinationCreateWithData(buffer as CFMutableData, type, 1, nil)!
            CGImageDestinationAddImageFromSource(cgDest, source, 0, properties as CFDictionary)
            precondition(CGImageDestinationFinalize(cgDest), "Finalize failed for \(file)")
            out = buffer as Data
        }

        let dest = getUrl(for: file)
        let ext = URL(fileURLWithPath: file).pathExtension
        var tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        if !ext.isEmpty { tempURL.appendPathExtension(ext) }
        try! out.write(to: tempURL)
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

    /// Set the like state by writing IPTC StarRating (5 = liked, 0 = not).
    /// Atomic: every step completes or the function crashes.
    public static func like(_ file: String, _ liked: Bool) {
        let url = getUrl(for: file)
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let type = CGImageSourceGetType(source)!

        let rating = liked ? 5 : 0
        let properties: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCStarRating: rating
            ] as [CFString: Any]
        ]

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, type, 1, nil)!
        CGImageDestinationAddImageFromSource(dest, source, 0, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(dest), "Finalize failed for \(file)")

        let actual = readIPTCInt(at: tempURL, key: kCGImagePropertyIPTCStarRating) ?? -1
        precondition(actual == rating,
                     "rating verify failed for \(file): expected \(rating), got \(actual)")

        _ = try! FileManager.default.replaceItemAt(url, withItemAt: tempURL)
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
            "saveAudio: file not present after move at \(dest.path)"
        )
    }

    /// Returns the URL of the lone audio file in `Documents/`, if any.
    public static func getAudio() -> URL? {
        getAllGenerations().first(where: isAudio)
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "caf", "aiff", "aif", "flac", "ogg", "opus"
    ]

    private static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Read the prompt from IPTC Caption/Abstract. Nil when absent.
    public static func getPrompt(_ file: String) -> String? {
        readIPTCString(at: getUrl(for: file), key: kCGImagePropertyIPTCCaptionAbstract)
    }

    /// Read the model from XMP CreatorTool. Nil when absent.
    public static func getModel(_ file: String) -> String? {
        let url = getUrl(for: file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:CreatorTool" as CFString) else {
            return nil
        }
        let raw = CGImageMetadataTagCopyValue(tag)
        let string = (raw as? String) ?? (raw as? NSString).map(String.init)
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    /// Read the like state from IPTC StarRating (`>= 1` = liked).
    public static func getLike(_ file: String) -> Bool {
        (readIPTCInt(at: getUrl(for: file), key: kCGImagePropertyIPTCStarRating) ?? 0) >= 1
    }

    private static func readIPTCString(at url: URL, key: CFString) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
              let value = iptc[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func readIPTCInt(at url: URL, key: CFString) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
              let value = iptc[key] as? NSNumber else {
            return nil
        }
        return value.intValue
    }

    public static func getUrl(for file: String) -> URL {
        documents.appendingPathComponent(URL(fileURLWithPath: file).lastPathComponent)
    }
}
