import XCTest
@testable import TrayCore

final class TrayStorageTests: XCTestCase {
    var base: URL!
    var storage: TrayStorage!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storage = try TrayStorage(root: base.appendingPathComponent("Tray"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: base) }
    func source(_ name: String, text: String = "original") throws -> URL {
        let url = base.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
    func testCopySurvivesOriginalDeletionAndRestart() throws {
        let original = try source("你好.txt")
        let item = try XCTUnwrap(storage.importFile(original, existing: []))
        try storage.save([item])
        try FileManager.default.removeItem(at: original)
        let reopened = try TrayStorage(root: storage.root)
        XCTAssertEqual(try reopened.load(), [item])
        XCTAssertEqual(try String(contentsOf: reopened.url(for: item)), "original")
    }
    func testRemovalNeverDeletesOriginal() throws {
        let original = try source("keep.txt")
        let item = try XCTUnwrap(storage.importFile(original, existing: []))
        try storage.save([item])
        XCTAssertTrue(try storage.remove([item.id], from: [item]).isEmpty)
        XCTAssertEqual(try String(contentsOf: original), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.url(for: item).path))
        XCTAssertTrue(try storage.load().isEmpty)
    }
    func testSameNameFilesStayIndependentAndDuplicateIsSkipped() throws {
        let first = try source("file.txt", text: "one")
        let other = base.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let second = other.appendingPathComponent("file.txt")
        try Data("two".utf8).write(to: second)
        let a = try XCTUnwrap(storage.importFile(first, existing: []))
        XCTAssertNil(try storage.importFile(first, existing: [a]))
        let b = try XCTUnwrap(storage.importFile(second, existing: [a]))
        XCTAssertNotEqual(storage.url(for: a), storage.url(for: b))
        XCTAssertEqual(try String(contentsOf: storage.url(for: a)), "one")
        XCTAssertEqual(try String(contentsOf: storage.url(for: b)), "two")
    }
    func testDirectoryContentsAreCopied() throws {
        let folder = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("note.txt"))
        let item = try XCTUnwrap(storage.importFile(folder, existing: []))
        XCTAssertTrue(item.isDirectory)
        XCTAssertEqual(try String(contentsOf: storage.url(for: item).appendingPathComponent("note.txt")), "nested")
    }
    func testRejectsRecursiveImports() throws {
        XCTAssertThrowsError(try storage.importFile(base, existing: []))
        XCTAssertThrowsError(try storage.importFile(storage.root, existing: []))
    }
    func testMissingSourceDoesNotChangeManifest() throws {
        let item = try XCTUnwrap(storage.importFile(source("good.txt"), existing: []))
        try storage.save([item])
        XCTAssertThrowsError(try storage.importFile(base.appendingPathComponent("missing"), existing: [item]))
        XCTAssertEqual(try storage.load(), [item])
    }
}
