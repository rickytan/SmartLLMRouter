import Foundation
import Swifter

class ProxyServer: ObservableObject {
    static let shared = ProxyServer()
    private let httpServer = HttpServer()
    
    @Published var isRunning: Bool = false
    @Published var port: Int = 1897
    
    private init() {
        setupRoutes()
    }
    
    func start() {
        do {
            try httpServer.start(in_port_t(port), forceIPv4: true)
            isRunning = true
            print("✅ Proxy started on port \(port)")
        } catch {
            print("❌ Failed to start proxy: \(error)")
            isRunning = false
        }
    }
    
    func stop() {
        httpServer.stop()
        isRunning = false
        print("🛑 Proxy stopped")
    }
    
    private func setupRoutes() {
        httpServer.post["/v1/messages"] = { [weak self] request in
            return self?.handleMessagesRequest(request) ?? .internalServerError
        }
        
        httpServer.post["/v1/chat/completions"] = { [weak self] request in
            return self?.handleChatCompletionsRequest(request) ?? .internalServerError
        }
    }
    
    private func handleMessagesRequest(_ request: HttpRequest) -> HttpResponse {
        // TODO: Implement Anthropic routing
        return .ok(.html("Anthropic request received"))
    }
    
    private func handleChatCompletionsRequest(_ request: HttpRequest) -> HttpResponse {
        // TODO: Implement OpenAI routing
        return .ok(.html("OpenAI request received"))
    }
}
