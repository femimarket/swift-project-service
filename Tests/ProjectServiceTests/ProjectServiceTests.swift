import Testing
import Foundation
import ImageIO
import CoreGraphics
import CoreVideo
import AVFoundation
import XMPToolkit
@testable import ProjectService

@Suite("ProjectService", .serialized)
struct ProjectServiceTests {
    let prefix = "psvc-test-\(UUID().uuidString)-"

    func name(_ stem: String) -> String { "\(prefix)\(stem)" }

    // MARK: - documents

    @Test func documentsIsAReadableDirectory() {
        let dir = ProjectService.documents
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - saveFile

    @Test func saveFileWithoutMetadataWritesBytesUnchanged() throws {
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let file = name("plain.bin")
        ProjectService.saveFile(bytes, named: file)
        let onDisk = try Data(contentsOf: ProjectService.getUrl(for: file))
        #expect(onDisk == bytes)
    }

    @Test func saveFileEmbedsPrompt() {
        let file = name("prompt.png")
        ProjectService.saveFile(makePNG(), named: file, prompt: "hello world")
        #expect(ProjectService.getPrompt(file) == "hello world")
    }

    @Test func saveFileEmbedsModel() {
        let file = name("model.png")
        ProjectService.saveFile(makePNG(), named: file, model: "dalle-3")
        #expect(ProjectService.getModel(file) == "dalle-3")
    }

    @Test func saveFileEmbedsBoth() {
        let file = name("both.png")
        ProjectService.saveFile(makePNG(), named: file, prompt: "p", model: "m")
        #expect(ProjectService.getPrompt(file) == "p")
        #expect(ProjectService.getModel(file) == "m")
    }

    @Test func saveFileWritesIptcExtAIPromptInformation() {
        let file = name("iptcext-prompt.png")
        ProjectService.saveFile(makePNG(), named: file, prompt: "what is AI")
        #expect(rawXMPProperty(file: file, ns: iptcExtNS, name: "AIPromptInformation") == "what is AI")
    }

    @Test func saveFileWritesIptcExtAISystemUsed() {
        let file = name("iptcext-model.png")
        ProjectService.saveFile(makePNG(), named: file, model: "dalle-3")
        #expect(rawXMPProperty(file: file, ns: iptcExtNS, name: "AISystemUsed") == "dalle-3")
    }

    @Test func saveFileEmbedsSubject() {
        let file = name("subject.png")
        ProjectService.saveFile(makePNG(), named: file, subject: ["cat", "fluffy", "studio"])
        #expect(ProjectService.getSubject(file) == ["cat", "fluffy", "studio"])
    }

    @Test func saveFileEmbedsAllThree() {
        let file = name("all.png")
        ProjectService.saveFile(makePNG(), named: file, prompt: "p", model: "m", subject: ["a", "b"])
        #expect(ProjectService.getPrompt(file) == "p")
        #expect(ProjectService.getModel(file) == "m")
        #expect(ProjectService.getSubject(file) == ["a", "b"])
    }

    @Test func getSubjectNilWhenAbsent() {
        let file = name("no-subject.png")
        ProjectService.saveFile(makePNG(), named: file)
        #expect(ProjectService.getSubject(file) == nil)
    }

    @Test func getSubjectNilWhenEmptyArrayPassed() {
        let file = name("empty-subject.png")
        ProjectService.saveFile(makePNG(), named: file, subject: [])
        #expect(ProjectService.getSubject(file) == nil)
    }

    // MARK: - saveFile (video, via Adobe XMP Toolkit smart handler)

    @Test func saveFileWithoutMetadataWritesVideoBytesUnchanged() async throws {
        let video = await makeMP4()
        let file = name("plain.mp4")
        ProjectService.saveFile(video, named: file)
        let onDisk = try Data(contentsOf: ProjectService.getUrl(for: file))
        #expect(onDisk == video)
    }

    @Test func saveFileEmbedsPromptInVideo() async {
        let file = name("video-prompt.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, prompt: "a video of a fox")
        #expect(ProjectService.getPrompt(file) == "a video of a fox")
    }

    @Test func saveFileEmbedsModelInVideo() async {
        let file = name("video-model.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, model: "sora-1")
        #expect(ProjectService.getModel(file) == "sora-1")
    }

    @Test func saveFileEmbedsSubjectInVideo() async {
        let file = name("video-subject.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, subject: ["fox", "wildlife"])
        #expect(ProjectService.getSubject(file) == ["fox", "wildlife"])
    }

    @Test func saveFileEmbedsAllThreeInVideo() async {
        let file = name("video-all.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, prompt: "p", model: "m", subject: ["a", "b"])
        #expect(ProjectService.getPrompt(file) == "p")
        #expect(ProjectService.getModel(file) == "m")
        #expect(ProjectService.getSubject(file) == ["a", "b"])
    }

    @Test func saveFileWritesIptcExtAIPromptInformationInVideo() async {
        let file = name("video-iptcext-prompt.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, prompt: "what is AI video")
        #expect(rawXMPProperty(file: file, ns: iptcExtNS, name: "AIPromptInformation") == "what is AI video")
    }

    @Test func saveFileWritesIptcExtAISystemUsedInVideo() async {
        let file = name("video-iptcext-model.mp4")
        ProjectService.saveFile(await makeMP4(), named: file, model: "sora-1")
        #expect(rawXMPProperty(file: file, ns: iptcExtNS, name: "AISystemUsed") == "sora-1")
    }

    @Test func saveFileOverwritesExisting() {
        let file = name("overwrite.png")
        ProjectService.saveFile(makePNG(), named: file, prompt: "first")
        ProjectService.saveFile(makePNG(), named: file, prompt: "second")
        #expect(ProjectService.getPrompt(file) == "second")
    }

    @Test func getPromptNilWhenAbsent() {
        let file = name("no-prompt.png")
        ProjectService.saveFile(makePNG(), named: file)
        #expect(ProjectService.getPrompt(file) == nil)
    }

    @Test func getModelNilWhenAbsent() {
        let file = name("no-model.png")
        ProjectService.saveFile(makePNG(), named: file)
        #expect(ProjectService.getModel(file) == nil)
    }

    // MARK: - like

    @Test func likeTrueThenRead() {
        let file = name("like.png")
        ProjectService.saveFile(makePNG(), named: file)
        ProjectService.like(file, true)
        #expect(ProjectService.getLike(file) == true)
    }

    @Test func likeFalseAfterTrue() {
        let file = name("unlike.png")
        ProjectService.saveFile(makePNG(), named: file)
        ProjectService.like(file, true)
        ProjectService.like(file, false)
        #expect(ProjectService.getLike(file) == false)
    }

    @Test func getLikeFalseWhenAbsent() {
        let file = name("never-liked.png")
        ProjectService.saveFile(makePNG(), named: file)
        #expect(ProjectService.getLike(file) == false)
    }

    // MARK: - getAllGenerations

    @Test func getAllGenerationsIncludesSaved() {
        let file = name("listed.png")
        ProjectService.saveFile(makePNG(), named: file)
        let all = ProjectService.getAllGenerations()
        #expect(all.contains { $0.lastPathComponent == file })
    }

    // MARK: - saveAudio / getAudio

    @Test func saveAudioWritesAndGetAudioReturnsIt() {
        let file = name("audio.m4a")
        ProjectService.saveAudio(Data([0xDE, 0xAD, 0xBE, 0xEF]), named: file)
        #expect(ProjectService.getAudio()?.lastPathComponent == file)
    }

    @Test func saveAudioDeletesPriorAudio() {
        let first = name("first.mp3")
        let second = name("second.wav")
        ProjectService.saveAudio(Data([0x01]), named: first)
        ProjectService.saveAudio(Data([0x02]), named: second)
        #expect(!FileManager.default.fileExists(atPath: ProjectService.getUrl(for: first).path))
        #expect(FileManager.default.fileExists(atPath: ProjectService.getUrl(for: second).path))
    }

    @Test func getAudioNilWhenNoAudioPresent() {
        for url in ProjectService.getAllGenerations() {
            let ext = url.pathExtension.lowercased()
            if ["mp3", "m4a", "wav", "aac", "caf", "aiff", "aif", "flac", "ogg", "opus"].contains(ext) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        #expect(ProjectService.getAudio() == nil)
    }

    @Test func saveAudioDoesNotDeleteImages() {
        let img = name("keep.png")
        let aud = name("audio.mp3")
        ProjectService.saveFile(makePNG(), named: img, prompt: "x")
        ProjectService.saveAudio(Data([0x01]), named: aud)
        #expect(FileManager.default.fileExists(atPath: ProjectService.getUrl(for: img).path))
        #expect(ProjectService.getPrompt(img) == "x")
    }

    // MARK: - getUrl

    @Test func getUrlPointsIntoDocuments() {
        let url = ProjectService.getUrl(for: "anything.png")
        #expect(url.deletingLastPathComponent().standardizedFileURL
                == ProjectService.documents.standardizedFileURL)
        #expect(url.lastPathComponent == "anything.png")
    }

    @Test func getUrlStripsPathTraversal() {
        let url = ProjectService.getUrl(for: "../../../etc/passwd")
        #expect(url.lastPathComponent == "passwd")
        #expect(url.deletingLastPathComponent().standardizedFileURL
                == ProjectService.documents.standardizedFileURL)
    }

    // MARK: - helpers

    private let iptcExtNS = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/"

    private func rawXMPProperty(file: String, ns: String, name: String) -> String? {
        let url = ProjectService.getUrl(for: file)
        var buf = [CChar](repeating: 0, count: 8192)
        let written = url.path.withCString { path in
            ns.withCString { nsPtr in
                name.withCString { namePtr in
                    buf.withUnsafeMutableBufferPointer { bufPtr in
                        psxmp_read_property(path, nsPtr, namePtr, bufPtr.baseAddress, Int32(bufPtr.count))
                    }
                }
            }
        }
        guard written > 0 else { return nil }
        let bytes = buf.prefix(Int(written)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func makePNG() -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: bitmapInfo.rawValue
        )!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = ctx.makeImage()!
        let buffer = NSMutableData()
        let dest = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        precondition(CGImageDestinationFinalize(dest))
        return buffer as Data
    }

    /// Build a tiny single-frame H.264 MP4 via AVAssetWriter.
    private func makeMP4() async -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 16,
            AVVideoHeightKey: 16,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb
        )
        adaptor.append(pb!, withPresentationTime: .zero)
        input.markAsFinished()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        precondition(writer.status == .completed, "MP4 writer failed: \(writer.error?.localizedDescription ?? "unknown")")
        let data = try! Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return data
    }
}
