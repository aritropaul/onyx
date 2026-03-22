import Foundation
import SwiftUI

@Observable
final class SyncManager: @unchecked Sendable {
    private let client = SyncClient()
    private(set) var isConnected = false
    private(set) var presences: [UInt64: UserPresence] = [:]

    var serverHost: String = "localhost"
    var serverPort: Int = 3001
    let clientId: UInt64 = UInt64.random(in: 1000...UInt64.max)

    /// Incremented on each remote change — observe this to trigger UI refresh.
    var remoteChangeVersion: Int = 0

    private var activeDocumentId: String?
    private var activeMarkdownText: String?

    // MARK: - Connection

    func connect(documentId: String, markdownText: String, authToken: String? = nil) async {
        activeDocumentId = documentId
        activeMarkdownText = markdownText

        var urlString = "ws://\(serverHost):\(serverPort)/docs/\(documentId)"
        if let token = authToken {
            urlString += "?token=\(token)"
        }
        let url = URL(string: urlString)!

        await client.setHandlers(
            onMessage: { [weak self] data in
                Task { @MainActor in
                    self?.handleMessage(data, documentId: documentId)
                }
            },
            onConnect: { [weak self] in
                Task { @MainActor in
                    self?.isConnected = true
                }
            },
            onDisconnect: { [weak self] in
                Task { @MainActor in
                    self?.isConnected = false
                }
            }
        )

        await client.connect(to: url)
    }

    func disconnect() async {
        await client.disconnect()
        isConnected = false
        activeDocumentId = nil
        activeMarkdownText = nil
    }

    // MARK: - Send

    func sendDocumentUpdate(documentId: String, text: String) {
        guard isConnected else { return }
        activeMarkdownText = text
        Task {
            guard let data = text.data(using: .utf8) else { return }
            var message = Data([0x02])
            message.append(data)
            await client.send(message)
        }
    }

    func sendAwareness(offset: Int?, userName: String) async {
        let awareness: [String: Any] = [
            "clientId": clientId,
            "userName": userName,
            "cursorOffset": offset ?? 0
        ]
        if let json = try? JSONSerialization.data(withJSONObject: awareness) {
            var message = Data([0x03])
            message.append(json)
            await client.send(message)
        }
    }

    // MARK: - Private

    @MainActor
    private func handleMessage(_ data: Data, documentId: String) {
        guard data.count > 0 else { return }
        let messageType = data[0]
        let payload = data.dropFirst()

        switch messageType {
        case 0x00: // SyncStep1
            handleSyncStep1(Data(payload), documentId: documentId)
        case 0x01: // SyncStep2
            handleSyncStep2(Data(payload), documentId: documentId)
        case 0x02: // Update
            handleUpdate(Data(payload), documentId: documentId)
        case 0x03: // Awareness
            handleAwareness(Data(payload))
        default:
            break
        }
    }

    @MainActor
    private func handleSyncStep1(_ stateVector: Data, documentId: String) {
        guard let text = activeMarkdownText,
              let data = text.data(using: .utf8) else { return }
        Task {
            var message = Data([0x01])
            message.append(data)
            await client.send(message)
        }
    }

    @MainActor
    private func handleSyncStep2(_ diff: Data, documentId: String) {
        if let text = String(data: diff, encoding: .utf8) {
            activeMarkdownText = text
        }
        remoteChangeVersion += 1
    }

    @MainActor
    private func handleUpdate(_ update: Data, documentId: String) {
        if let text = String(data: update, encoding: .utf8) {
            activeMarkdownText = text
        }
        remoteChangeVersion += 1
    }

    @MainActor
    private func handleAwareness(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remoteId = (json["clientId"] as? NSNumber)?.uint64Value else { return }

        // Don't show our own cursor
        guard remoteId != clientId else { return }

        let colorIndex = Int(remoteId % UInt64(OnyxTheme.Colors.cursorColors.count))

        let presence = UserPresence(
            id: remoteId,
            userName: json["userName"] as? String ?? "Anonymous",
            color: OnyxTheme.Colors.cursorColors[colorIndex],
            cursorOffset: json["cursorOffset"] as? Int,
            lastSeen: Date()
        )
        presences[remoteId] = presence
    }
}
