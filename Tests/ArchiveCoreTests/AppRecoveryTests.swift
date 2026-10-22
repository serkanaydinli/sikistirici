import XCTest
import ArchiveCore
@testable import SikistiriciApp

final class AppRecoveryTests: XCTestCase {
    @MainActor private func makeModel() -> AppModel {
        let suite = "AppRecoveryTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
        addTeardownBlock { preferences.removePersistentDomain(forName: suite) }
        return AppModel(preferences: preferences)
    }
    @MainActor func testCancelledAndStalePasswordResponsesDoNotRunWork() {
        let model = makeModel()
        let old = PasswordRequest(url: URL(fileURLWithPath: "/old.zip"))
        model.passwordRequest = old
        model.cancelRecovery()
        model.submitPassword("secret", request: old)
        XCTAssertNil(model.archivePassword)
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.jobs.isEmpty)
    }
    @MainActor func testInvalidLimitCannotBeAccepted() {
        let model = makeModel()
        model.raiseLimitAndRetry(100, requestID: UUID())
        XCTAssertEqual(model.expansionLimitGB, 20)
        XCTAssertFalse(model.loading)
    }

    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppRecovery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("encrypted payload".utf8).write(to: root.appendingPathComponent("secret.txt"))
        let zip = root.appendingPathComponent("payload.zip")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root; process.arguments = ["-q", "-P", "test-password", zip.path, "secret.txt"]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        return (root, zip)
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Model operation timed out")
    }
    @MainActor func testPayloadEncryptedZIPPreviewRetriesCapturedEntry() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.openArchive(zip)
        try await wait { !model.loading }
        XCTAssertTrue(model.archiveReady); XCTAssertNil(model.archivePassword)
        model.selection = ["secret.txt"]; model.previewSelected()
        try await wait { !model.previewLoading }
        let request = try XCTUnwrap(model.passwordRequest)
        model.selection = [] // Retry must preserve the original preview target.
        model.submitPassword("wrong", request: request)
        try await wait { model.passwordRequest != nil }
        let corrected = try XCTUnwrap(model.passwordRequest)
        model.submitPassword("test-password", request: corrected)
        try await wait { !model.previewLoading }
        XCTAssertNil(model.passwordRequest)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(model.previewURL), encoding: .utf8), "encrypted payload")
        XCTAssertEqual(model.archivePassword, "test-password")
        model.closeArchive()
    }
    @MainActor func testVerifyRetryAndExtractionPreserveQueuedTarget() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.openArchive(zip)
        try await wait { !model.loading }
        model.testArchive()
        try await wait { model.passwordRequest != nil }
        model.submitPassword("test-password", request: try XCTUnwrap(model.passwordRequest))
        try await wait { !model.hasPendingJobs }
        XCTAssertEqual(model.jobs.first?.state, .done)
        let destination = root.appendingPathComponent("original-output")
        model.enqueue(.extract(zip, destination, ["secret.txt"], nil, .rename), title: "Extract", subtitle: "")
        try await wait { model.passwordRequest != nil }
        model.selection = []; model.filenameEncoding = .automatic
        model.submitPassword("test-password", request: try XCTUnwrap(model.passwordRequest))
        try await wait { !model.hasPendingJobs }
        XCTAssertEqual(model.jobs.first?.state, .done)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("secret.txt"), encoding: .utf8), "encrypted payload")
        model.closeArchive()
    }
    @MainActor func testCancellingRecoveryPreventsExtractionAndStaleResponse() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.openArchive(zip); try await wait { !model.loading }
        let destination = root.appendingPathComponent("cancelled-output")
        model.enqueue(.extract(zip, destination, nil, nil, .rename), title: "Extract", subtitle: "")
        try await wait { model.passwordRequest != nil }
        let request = try XCTUnwrap(model.passwordRequest)
        model.cancelRecovery(); model.submitPassword("test-password", request: request)
        XCTAssertEqual(model.jobs.first?.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("secret.txt").path))
        XCTAssertNil(model.archivePassword)
        model.closeArchive()
    }
    @MainActor func testSwitchingArchiveInvalidatesPreviewPasswordResponse() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.openArchive(zip); try await wait { !model.loading }
        model.selection = ["secret.txt"]; model.previewSelected()
        try await wait { model.passwordRequest != nil }
        let request = try XCTUnwrap(model.passwordRequest)
        let other = root.appendingPathComponent("missing.zip")
        model.openArchive(other)
        model.submitPassword("test-password", request: request)
        try await wait { !model.loading }
        XCTAssertEqual(model.archiveURL, other); XCTAssertNil(model.archivePassword)
        XCTAssertFalse(model.showingPreview); XCTAssertNil(model.previewURL)
        model.closeArchive()
    }
    @MainActor func testSizeFailureOffersExplicitRetryWithoutOpeningOtherArchive() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.expansionLimitGB = 1.0 / 1_073_741_824
        model.openArchive(zip); try await wait { !model.loading }
        XCTAssertFalse(model.archiveReady)
        let request = try XCTUnwrap(model.sizeLimitRequest)
        XCTAssertEqual(model.expansionLimitGB, 1.0 / 1_073_741_824)
        model.raiseLimitAndRetry(1, requestID: request.id)
        try await wait { !model.loading }
        XCTAssertTrue(model.archiveReady); XCTAssertEqual(model.archiveURL, zip)
        XCTAssertEqual(model.expansionLimitGB, 1)
        model.closeArchive()
    }

    @MainActor func testTerminationCancelsPendingRecoveryAndQueuedWork() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.openArchive(zip); try await wait { !model.loading }
        let destination = root.appendingPathComponent("quit-output")
        model.enqueue(.extract(zip, destination, nil, nil, .rename), title: "First", subtitle: "")
        model.enqueue(.verify(zip, "test-password"), title: "Queued", subtitle: "")
        try await wait { model.passwordRequest != nil }
        await model.cancelAndWaitForTermination()
        XCTAssertFalse(model.hasPendingJobs)
        XCTAssertTrue(model.jobs.allSatisfy { $0.state == .cancelled })
        XCTAssertNil(model.passwordRequest); XCTAssertNil(model.archivePassword)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("secret.txt").path))
    }

    @MainActor func testHeaderPasswordSurvivesExplicitSizeRetry() async throws {
        let (root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let engine = ArchiveEngine(executable: project.appendingPathComponent("Sources/SikistiriciApp/Resources/7zz"))
        let archive = root.appendingPathComponent("headers.7z")
        _ = try engine.create(inputs: [root.appendingPathComponent("secret.txt")], destination: archive, format: .sevenZip, password: "test-password")
        let model = makeModel(); model.expansionLimitGB = 1.0 / 1_073_741_824
        model.openArchive(archive); try await wait { model.passwordRequest != nil }
        model.submitPassword("test-password", request: try XCTUnwrap(model.passwordRequest))
        try await wait { model.sizeLimitRequest != nil }
        model.raiseLimitAndRetry(1, requestID: try XCTUnwrap(model.sizeLimitRequest).id)
        try await wait { !model.loading }
        XCTAssertTrue(model.archiveReady); XCTAssertNil(model.passwordRequest)
        XCTAssertEqual(model.archivePassword, "test-password")
        model.closeArchive()
    }
    @MainActor func testCloseInvalidatesSizeRetry() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(); model.expansionLimitGB = 1.0 / 1_073_741_824
        model.openArchive(zip); try await wait { model.sizeLimitRequest != nil }
        let request = try XCTUnwrap(model.sizeLimitRequest)
        model.closeArchive(); model.raiseLimitAndRetry(1, requestID: request.id)
        XCTAssertNil(model.archiveURL); XCTAssertFalse(model.loading)
        XCTAssertEqual(model.expansionLimitGB, 1.0 / 1_073_741_824)
    }

    @MainActor func testTerminationWaitsForRunningOperationCallback() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel()
        model.enqueue(.verify(zip, "test-password"), title: "Running", subtitle: "")
        XCTAssertTrue(model.hasPendingJobs)
        await model.cancelAndWaitForTermination()
        XCTAssertFalse(model.hasPendingJobs)
        XCTAssertEqual(model.jobs.first?.state, .cancelled)
        XCTAssertNotNil(model.jobs.first?.finishedAt)
    }
    @MainActor func testUnsafePathIsNotOfferedSizeOverride() async throws {
        let (root, zip) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("unsafe".utf8).write(to: root.appendingPathComponent("with:colon.txt"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root; process.arguments = ["-q", zip.path, "with:colon.txt"]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let model = makeModel(); model.openArchive(zip); try await wait { !model.loading }
        XCTAssertFalse(model.archiveReady); XCTAssertNil(model.sizeLimitRequest)
        XCTAssertNotNil(model.errorMessage)
        model.closeArchive()
    }
}
