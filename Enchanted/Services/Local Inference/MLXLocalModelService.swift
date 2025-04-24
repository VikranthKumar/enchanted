//
//  MLXLocalModelService.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import Foundation
import Combine
import SwiftUI
import OllamaKit
import MLX

/// Service for managing local MLX models and inference
@Observable
class MLXLocalModelService: @unchecked Sendable {
    static let shared = MLXLocalModelService()
    
    // Model directory
    private let modelDirectoryURL: URL
    
    // Published properties
    var downloadProgress: [String: Double] = [:]
    var isDownloading: Bool = false
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservers: [String: NSKeyValueObservation] = [:]
    private var mlxInstances: [String: MLXLLM] = [:]
    
    init() {
        // Create directory for storing models
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDirectory = documentsDirectory.appendingPathComponent("mlx-models", isDirectory: true)
        
        // Create models directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create MLX models directory: \(error)")
            }
        }
        
        self.modelDirectoryURL = modelsDirectory
    }
    
    /// Initialize the models directory
    func initializeModels() async {
        print("Initializing MLX local models directory")
        
        let fileManager = FileManager.default
        
        // Ensure the models directory exists
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created MLX models directory at: \(modelDirectoryURL.path)")
            } catch {
                print("Failed to create MLX models directory: \(error)")
            }
        }
        
        // Check what models are available
        do {
            let modelFiles = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodel" || $0.pathExtension == "gguf" }
            
            print("Found \(modelFiles.count) local MLX model files:")
            for file in modelFiles {
                print("- \(file.lastPathComponent)")
            }
        } catch {
            print("Failed to list local MLX models: \(error)")
        }
    }
    
    /// Get list of available models
    func getModels() async throws -> [LanguageModel] {
        print("Checking for local MLX models at: \(modelDirectoryURL.path)")
        
        let fileManager = FileManager.default
        
        // Make sure directory exists
        if !fileManager.fileExists(atPath: modelDirectoryURL.path) {
            try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            print("Created MLX models directory")
            return []
        }
        
        // Get downloaded models
        let modelFiles = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodel" || $0.pathExtension == "gguf" }
        
        print("Found \(modelFiles.count) local MLX model files")
        
        let models = modelFiles.map { fileURL in
            let modelName = fileURL.deletingPathExtension().lastPathComponent
            print("Found local MLX model: \(modelName)")
            return LanguageModel(
                name: modelName,
                provider: .local,
                imageSupport: false
            )
        }
        
        return models
    }
    
    /// Download a model
    func downloadModel(model: MLXModelDownloadInfo) {
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
                let modelURL = self.modelDirectoryURL.appendingPathComponent("\(model.name).\(model.fileExtension)")
                
                do {
                    if fileManager.fileExists(atPath: modelURL.path) {
                        try fileManager.removeItem(at: modelURL)
                    }
                    
                    try fileManager.moveItem(at: tempURL, to: modelURL)
                    
                    // If we have a tokenizer URL, download that too
                    if let tokenizerURL = model.tokenizerURL {
                        self.downloadTokenizer(for: model, tokenizerURL: tokenizerURL)
                    } else {
                        // Set progress to 1.0 to indicate completion
                        self.downloadProgress[model.name] = 1.0
                        
                        // Delay removing progress to ensure UI updates
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.downloadProgress[model.name] = nil
                            self.isDownloading = self.downloadTasks.count > 0
                            
                            // Notify that download is complete
                            NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                        }
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
    
    /// Download tokenizer for a model
    private func downloadTokenizer(for model: MLXModelDownloadInfo, tokenizerURL: URL) {
        let session = URLSession.shared
        let task = session.downloadTask(with: tokenizerURL) { [weak self] (tempURL, response, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("Tokenizer download error: \(error.localizedDescription)")
                    // Even if tokenizer fails, we consider the model download complete
                    self.downloadProgress[model.name] = 1.0
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.downloadProgress[model.name] = nil
                        self.isDownloading = self.downloadTasks.count > 0
                        NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                    }
                    return
                }
                
                guard let tempURL = tempURL else {
                    print("Tokenizer download failed: No temporary URL")
                    // Even if tokenizer fails, we consider the model download complete
                    self.downloadProgress[model.name] = 1.0
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.downloadProgress[model.name] = nil
                        self.isDownloading = self.downloadTasks.count > 0
                        NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                    }
                    return
                }
                
                let fileManager = FileManager.default
                let tokenizerURL = self.modelDirectoryURL.appendingPathComponent("\(model.name).tokenizer")
                
                do {
                    if fileManager.fileExists(atPath: tokenizerURL.path) {
                        try fileManager.removeItem(at: tokenizerURL)
                    }
                    
                    try fileManager.moveItem(at: tempURL, to: tokenizerURL)
                    
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
                    print("Failed to save tokenizer: \(error)")
                    // Even if saving tokenizer fails, we consider the model download complete
                    self.downloadProgress[model.name] = 1.0
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.downloadProgress[model.name] = nil
                        self.isDownloading = self.downloadTasks.count > 0
                        NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                    }
                }
            }
        }
        
        task.resume()
    }
    
    /// Cancel model download
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
    
    /// Delete a model
    func deleteModel(name: String) throws {
        // Remove model file
        let modelExtensions = ["mlpackage", "mlmodel", "gguf"]
        
        for ext in modelExtensions {
            let modelURL = modelDirectoryURL.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
        }
        
        // Remove tokenizer file
        let tokenizerURL = modelDirectoryURL.appendingPathComponent("\(name).tokenizer")
        if FileManager.default.fileExists(atPath: tokenizerURL.path) {
            try FileManager.default.removeItem(at: tokenizerURL)
        }
        
        // Remove from instances
        mlxInstances[name] = nil
        
        // Notify that model was deleted
        NotificationCenter.default.post(name: NSNotification.Name("ModelDeleted"), object: name)
    }
    
    /// Check if model exists
    func modelExists(name: String) -> Bool {
        let modelExtensions = ["mlpackage", "mlmodel", "gguf"]
        
        for ext in modelExtensions {
            let modelURL = modelDirectoryURL.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                return true
            }
        }
        
        return false
    }
    
    /// Get or create MLX model instance
    private func getOrCreateMLXInstance(for modelName: String) throws -> MLXLLM {
        if let instance = mlxInstances[modelName] {
            return instance
        }
        
        // Check all model extensions
        let modelExtensions = ["mlpackage", "mlmodel", "gguf"]
        var modelPath: String?
        var modelExt: String?
        
        for ext in modelExtensions {
            let path = modelDirectoryURL.appendingPathComponent("\(modelName).\(ext)").path
            if FileManager.default.fileExists(atPath: path) {
                modelPath = path
                modelExt = ext
                break
            }
        }
        
        guard let modelPath = modelPath, let modelExt = modelExt else {
            throw MLXModelError.modelNotFound
        }
        
        // Check for tokenizer
        let tokenizerPath = modelDirectoryURL.appendingPathComponent("\(modelName).tokenizer").path
        if !FileManager.default.fileExists(atPath: tokenizerPath) {
            throw MLXModelError.tokenizerNotFound
        }
        
        // Determine prompt format based on model name
        let promptFormat: ModelPromptFormat
        let modelNameLower = modelName.lowercased()
        
        if modelNameLower.contains("llama-3") || modelNameLower.contains("llama3") {
            promptFormat = .llama3
        } else if modelNameLower.contains("llama-2") || modelNameLower.contains("llama2") {
            promptFormat = .llama2
        } else if modelNameLower.contains("phi") {
            promptFormat = .phi
        } else if modelNameLower.contains("gemma") {
            promptFormat = .gemma
        } else if modelNameLower.contains("mistral") {
            promptFormat = .mistral
        } else {
            // Default to llama3 format
            promptFormat = .llama3
        }
        
        // Get system prompt from settings
        let systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt")
        
        // Create the model instance
        let model = try MLXLLM(
            modelPath: modelPath,
            tokenizerPath: tokenizerPath,
            promptFormat: promptFormat,
            systemPrompt: systemPrompt
        )
        
        // Store the instance for reuse
        mlxInstances[modelName] = model
        return model
    }
    
    /// Generate a response using MLX
    func chat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        return Future<AnyPublisher<OKChatResponse, Error>, Error> { [weak self] promise in
            Task {
                do {
                    guard let self = self else {
                        throw MLXModelError.modelNotInitialized
                    }
                    
                    // Get the MLX model instance
                    let mlxInstance = try self.getOrCreateMLXInstance(for: data.model)
                    
                    // Extract system message if available
                    if let systemMessage = data.messages.first(where: { $0.role == .system }) {
                        if mlxInstance.template.systemPrompt == nil {
                            // Create a new template with the system prompt
                            var updatedTemplate = mlxInstance.template
                            updatedTemplate.systemPrompt = systemMessage.content
                            mlxInstance.template = updatedTemplate
                        }
                    }
                    
                    // Convert message history
                    mlxInstance.history = self.convertToChatObjects(from: data.messages)
                    
                    // Get the latest user message
                    guard let lastUserMessage = data.messages.last(where: { $0.role == .user })?.content else {
                        throw MLXModelError.inferenceError("No user message found")
                    }
                    
                    // Set up publisher to stream tokens
                    let subject = PassthroughSubject<OKChatResponse, Error>()
                    let publisher = subject.eraseToAnyPublisher()
                    
                    // Set callback for updates
                    mlxInstance.updateCallback = { delta in
                        if let delta = delta {
                            // Generate response
                            let responseDict: [String: Any] = [
                                "model": data.model,
                                "message": [
                                    "role": "assistant",
                                    "content": MLXTokenSanitizer.sanitize(token: delta)
                                ],
                                "done": false
                            ]
                            
                            do {
                                let jsonData = try JSONSerialization.data(withJSONObject: responseDict)
                                let response = try JSONDecoder().decode(OKChatResponse.self, from: jsonData)
                                subject.send(response)
                            } catch {
                                subject.send(completion: .failure(error))
                            }
                        } else {
                            // Completion
                            let responseDict: [String: Any] = [
                                "model": data.model,
                                "message": [
                                    "role": "assistant",
                                    "content": ""
                                ],
                                "done": true
                            ]
                            
                            do {
                                let jsonData = try JSONSerialization.data(withJSONObject: responseDict)
                                let response = try JSONDecoder().decode(OKChatResponse.self, from: jsonData)
                                subject.send(response)
                                subject.send(completion: .finished)
                            } catch {
                                subject.send(completion: .failure(error))
                            }
                        }
                    }
                    
                    // Start inference
                    Task {
                        await mlxInstance.respond(to: lastUserMessage)
                    }
                    
                    promise(.success(publisher))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .switchToLatest()
        .eraseToAnyPublisher()
    }
    
    /// Convert OllamaKit messages to MLX messages
    private func convertToChatObjects(from messages: [OKChatRequestData.Message]) -> [MLXMessage] {
        return messages.map { message in
            let role: Role
            switch message.role {
                case .user:
                    role = .user
                case .assistant:
                    role = .bot
                case .system:
                    role = .system
            }
            return MLXMessage(role: role, content: message.content)
        }
    }
    
    /// Check if server is reachable
    func reachable() async -> Bool {
        return true // Always reachable for local models
    }
}

