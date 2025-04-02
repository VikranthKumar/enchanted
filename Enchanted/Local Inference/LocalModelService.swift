//
//  LocalModelService.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import Foundation
import Combine
import OllamaKit
import SwiftUI
import SwiftLlama

@Observable
class LocalModelService: @unchecked Sendable {
    static let shared = LocalModelService()
    
    // Model directory
    private let modelDirectoryURL: URL
    
    // Published properties for downloaded models and download progress
    var downloadProgress: [String: Double] = [:]
    var isDownloading: Bool = false
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]
    private var swiftLlamaInstances: [String: SwiftLlama] = [:]
    
    
    init() {
        // Create directory for storing models
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDirectory = documentsDirectory.appendingPathComponent("models", isDirectory: true)
        
        // Create models directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create models directory: \(error)")
            }
        }
        
        self.modelDirectoryURL = modelsDirectory
    }
    
    func initializeModels() async {
        print("Initializing local models directory")
        
        let fileManager = FileManager.default
        
        // Ensure the models directory exists
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created models directory at: \(modelDirectoryURL.path)")
            } catch {
                print("Failed to create models directory: \(error)")
            }
        }
        
        // Check what models are available
        do {
            let modelFiles = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "gguf" }
            
            print("Found \(modelFiles.count) local model files:")
            for file in modelFiles {
                print("- \(file.lastPathComponent)")
            }
        } catch {
            print("Failed to list local models: \(error)")
        }
    }
    
    // Update getModels to check directory first
    func getModels() async throws -> [LanguageModel] {
        print("Checking for local models at: \(modelDirectoryURL.path)")
        
        let fileManager = FileManager.default
        
        // Make sure directory exists
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            print("Created models directory")
            return []
        }
        
        // Get downloaded models
        let modelFiles = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "gguf" }
        
        print("Found \(modelFiles.count) local model files")
        
        let models = modelFiles.map { fileURL in
            let modelName = fileURL.deletingPathExtension().lastPathComponent
            print("Found local model: \(modelName)")
            return LanguageModel(
                name: modelName,
                provider: .local,
                imageSupport: false
            )
        }
        
        return models
    }
    
    // Download a model
    func downloadModel(model: ModelDownloadInfo) {
        // Immediately set download progress to show UI feedback
        DispatchQueue.main.async {
            self.downloadProgress[model.name] = 0.0
            self.isDownloading = true
        }
        
        let session = URLSession.shared
        let task = session.downloadTask(with: model.url) { [weak self] (tempURL, response, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Download error: \(error.localizedDescription)")
                    self.downloadProgress[model.name] = nil
                    self.isDownloading = false
                    return
                }
                
                guard let tempURL = tempURL else {
                    print("Download failed: No temporary URL")
                    self.downloadProgress[model.name] = nil
                    self.isDownloading = false
                    return
                }
                
                let fileManager = FileManager.default
                let modelURL = self.modelDirectoryURL.appendingPathComponent("\(model.name).gguf")
                
                do {
                    if fileManager.fileExists(atPath: modelURL.path) {
                        try fileManager.removeItem(at: modelURL)
                    }
                    
                    try fileManager.moveItem(at: tempURL, to: modelURL)
                    
                    // Set progress to 1.0 to indicate completion
                    self.downloadProgress[model.name] = 1.0
                    
                    // Delay removing progress to ensure UI updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.downloadProgress[model.name] = nil
                        self.isDownloading = self.downloadTasks.count > 0
                        
                        // Notify that download is complete
                        NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                    }
                } catch {
                    print("Failed to save model: \(error)")
                    self.downloadProgress[model.name] = nil
                    self.isDownloading = false
                }
            }
        }
        
        task.resume()
        downloadTasks[model.name] = task
        
        // Monitor download progress
        let progressObserver = task.progress.observe(\.fractionCompleted) { [weak self] (progress, _) in
            DispatchQueue.main.async {
                self?.downloadProgress[model.name] = progress.fractionCompleted
            }
        }
        
        progressObservers[model.name] = progressObserver
    }
    
    // Cancel download
    func cancelDownload(name: String) {
        downloadTasks[name]?.cancel()
        downloadTasks[name] = nil
        progressObservers[name]?.invalidate()
        progressObservers[name] = nil
        downloadProgress[name] = nil
        
        if downloadTasks.isEmpty {
            isDownloading = false
        }
    }
    
    // Delete model
    func deleteModel(name: String) throws {
        let modelURL = modelDirectoryURL.appendingPathComponent("\(name).gguf")
        try FileManager.default.removeItem(at: modelURL)
        swiftLlamaInstances[name] = nil
        NotificationCenter.default.post(name: NSNotification.Name("ModelDeleted"), object: name)
    }
    
    // Check if model exists
    func modelExists(name: String) -> Bool {
        let modelURL = modelDirectoryURL.appendingPathComponent("\(name).gguf")
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    // Initialize model if needed
    private func getOrCreateLlamaInstance(for modelName: String) throws -> SwiftLlama {
        if let instance = swiftLlamaInstances[modelName] {
            return instance
        }
        
        let modelURL = modelDirectoryURL.appendingPathComponent("\(modelName).gguf")
        
        if !FileManager.default.fileExists(atPath: modelURL.path) {
            throw LocalModelError.modelNotFound
        }
        
        do {
            let model = try SwiftLlama(modelPath: modelURL.path)
            swiftLlamaInstances[modelName] = model
            return model
        } catch {
            print("Failed to initialize SwiftLlama for model \(modelName): \(error)")
            throw LocalModelError.failedToLoadModel
        }
    }
    
    // Convert OllamaKit messages to SwiftLlama Chat objects
    private func convertToSwiftLlamaChats(from messages: [OKChatRequestData.Message]) -> [Chat] {
        var chats: [Chat] = []
        var currentUserMessage: String?
        
        // Group user-assistant pairs into Chat objects
        for i in 0..<messages.count {
            let message = messages[i]
            
            // Skip system messages
            if message.role == .system {
                continue
            }
            
            if message.role == .user {
                currentUserMessage = message.content
            } else if message.role == .assistant, let userMsg = currentUserMessage {
                // Create a chat pair
                chats.append(Chat(user: userMsg, bot: message.content))
                currentUserMessage = nil
            }
        }
        
        return chats
    }
    
    // Get prompt type for a model
    private func getPromptType(for modelName: String) -> Prompt.`Type` {
        let modelInfo = LocalModelService.availableModels.first { $0.name == modelName }
        
        switch modelInfo?.promptFormat {
            case .llama2:
                return .llama
            case .llama3:
                return .llama3
            case .gemma:
                return .gemma
            case .phi:
                return .phi
            case nil:
                // Default to llama2 format if unknown
                return .llama
        }
    }
    
    // Generate a response from the model using SwiftLlama
    func chat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        return Future<AnyPublisher<OKChatResponse, Error>, Error> { [weak self] promise in
            Task {
                do {
                    guard let self = self else {
                        throw LocalModelError.modelNotInitialized
                    }
                    
                    let llamaInstance = try self.getOrCreateLlamaInstance(for: data.model)
                    
                    // Get system prompt if available
                    let systemPrompt = data.messages.first(where: { $0.role == .system })?.content ?? ""
                    
                    // Get the latest user message
                    guard let userMessage = data.messages.last(where: { $0.role == .user })?.content else {
                        throw LocalModelError.inferenceError("No user message found")
                    }
                    
                    // Convert previous messages to Chat objects for history
                    // Only include full user-assistant pairs, not the latest user message
                    let messagesToConvert = data.messages.prefix(while: { $0.content != userMessage || $0.role != .user })
                    let history = self.convertToSwiftLlamaChats(from: Array(messagesToConvert))
                    
                    // Get the prompt type for this model
                    let promptType = self.getPromptType(for: data.model)
                    
                    // Create a properly formatted Prompt object
                    let prompt = Prompt(
                        type: promptType,
                        systemPrompt: systemPrompt,
                        userMessage: userMessage,
                        history: history
                    )
                    
                    // Use SwiftLlama's publisher for streaming
                    let modelName = data.model
                    let publisher = try await llamaInstance.start(for: prompt)
                        .map { self.tokenToResponse(token: $0, model: modelName) }
                        .eraseToAnyPublisher()
                    
                    promise(.success(publisher))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .switchToLatest()
        .eraseToAnyPublisher()
    }
    
    func tokenToResponse(token: String, model: String) -> OKChatResponse {
        let processedToken = TokenSanitizer.sanitize(token: token)
        
        // Use JSONSerialization to create the response
        let responseDict: [String: Any] = [
            "model": model,
            "message": [
                "role": "assistant",
                "content": processedToken
            ],
            "done": false
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: responseDict)
            let response = try JSONDecoder().decode(OKChatResponse.self, from: jsonData)
            return response
        } catch {
            // If decoding fails, create a fallback response
            print("Error creating OKChatResponse: \(error)")
            
            // Return an empty response that matches the structure but won't crash
            // This is a last resort fallback
            let emptyResponseDict: [String: Any] = [
                "model": model,
                "created_at": Date().timeIntervalSince1970,
                "message": [
                    "role": "assistant",
                    "content": "Error: \(error.localizedDescription)"
                ],
                "done": false
            ]
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: emptyResponseDict)
                return try JSONDecoder().decode(OKChatResponse.self, from: jsonData)
            } catch {
                // If even this fails, we have a serious issue
                fatalError("Could not create OKChatResponse: \(error)")
            }
        }
    }
    
    // Check if server is reachable (always returns true for local inference)
    func reachable() async -> Bool {
        return true
    }
}

// Add the phi prompt format
enum ModelPromptFormat {
    case llama2
    case llama3
    case gemma
    case phi
}

// Model download information
struct ModelDownloadInfo: Identifiable {
    var id: String { name }
    var name: String
    var displayName: String
    var url: URL
    var size: String
    var promptFormat: ModelPromptFormat
}

// Error types
enum LocalModelError: Error, LocalizedError {
    case modelNotFound
    case modelNotInitialized
    case failedToLoadModel
    case incompatibleModel
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
            case .modelNotFound:
                return "Model file not found on device"
            case .modelNotInitialized:
                return "Failed to initialize model"
            case .failedToLoadModel:
                return "Failed to load model"
            case .incompatibleModel:
                return "Model is not compatible with this device"
            case .inferenceError(let details):
                return "Inference error: \(details)"
        }
    }
    
    var failureReason: String? {
        switch self {
            case .modelNotFound:
                return "The model file was not found in the local storage directory"
            case .modelNotInitialized:
                return "The model could not be initialized by SwiftLlama"
            case .failedToLoadModel:
                return "There was an error loading the model"
            case .incompatibleModel:
                return "This model format is not supported by the current version of SwiftLlama"
            case .inferenceError(let details):
                return details
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
            case .modelNotFound:
                return "Try downloading the model again"
            case .modelNotInitialized:
                return "Restart the app and try again"
            case .failedToLoadModel:
                return "Try downloading a different model or check your device's available memory"
            case .incompatibleModel:
                return "Try a different model or update the app"
            case .inferenceError:
                return "Try a different prompt or restart the app"
        }
    }
}
