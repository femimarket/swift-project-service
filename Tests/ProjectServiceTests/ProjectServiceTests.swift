import Testing
import Foundation
import ImageIO
import CoreGraphics
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
        #expect(rawXMPTag(file: file, path: "Iptc4xmpExt:AIPromptInformation") == "what is AI")
    }

    @Test func saveFileWritesIptcExtAISystemUsed() {
        let file = name("iptcext-model.png")
        ProjectService.saveFile(makePNG(), named: file, model: "dalle-3")
        #expect(rawXMPTag(file: file, path: "Iptc4xmpExt:AISystemUsed") == "dalle-3")
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

    private func rawXMPTag(file: String, path: String) -> String? {
        let url = ProjectService.getUrl(for: file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else {
            return nil
        }
        let raw = CGImageMetadataTagCopyValue(tag)
        return (raw as? String) ?? (raw as? NSString).map(String.init)
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
}
