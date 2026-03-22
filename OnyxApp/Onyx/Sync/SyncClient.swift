import Foundation

actor SyncClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var serverURL: URL?
    private var isConnected = false
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30

    private var onMessage: (@Sendable (Data) -> Void)?
    private var onConnect: (@Sendable () -> Void)?
    private var onDisconnect: (@Sendable () -> Void)?

    func setHandlers(
        onMessage: @escaping @Sendable (Data) -> Void,
        onConnect: @escaping @Sendable () -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        self.onMessage = onMessage
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    func connect(to url: URL) {
        serverURL = url
        reconnectAttempt = 0
        doConnect()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func send(_ data: Data) {
        guard isConnected else { return }
        webSocketTask?.send(.data(data)) { error in
            if let error {
                print("[SyncClient] Send error: \(error)")
            }
        }
    }

    // MARK: - Private

    private func doConnect() {
        guard let url = serverURL else { return }
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        isConnected = true
        reconnectAttempt = 0
        onConnect?()
        receiveLoop()
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        await self.handleMessage(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            await self.handleMessage(data)
                        }
                    @unknown default:
                        break
                    }
                    await self.receiveLoop()

                case .failure(let error):
                    print("[SyncClient] Receive error: \(error)")
                    await self.handleDisconnect()
                }
            }
        }
    }

    private func handleMessage(_ data: Data) {
        onMessage?(data)
    }

    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
        onDisconnect?()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            doConnect()
        }
    }
}
