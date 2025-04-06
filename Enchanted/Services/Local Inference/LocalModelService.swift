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
import llama

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
    private var llamaInstances: [String: LLM] = [:]
    
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
//        try deleteAllModels()
        let modelURL = modelDirectoryURL.appendingPathComponent("\(name).gguf")
        try FileManager.default.removeItem(at: modelURL)
        llamaInstances[name] = nil
        NotificationCenter.default.post(name: NSNotification.Name("ModelDeleted"), object: name)
    }
    
//    func deleteAllModels() throws {
//        let fileManager = FileManager.default
//        let fileURLs = try fileManager.contentsOfDirectory(at: modelDirectoryURL, includingPropertiesForKeys: nil)
//        
//        for fileURL in fileURLs {
//            try fileManager.removeItem(at: fileURL)
//            
//            // If your models are named like "modelname.gguf", remove them from llamaInstances
//            let fileName = fileURL.deletingPathExtension().lastPathComponent
//            llamaInstances[fileName] = nil
//            NotificationCenter.default.post(name: NSNotification.Name("ModelDeleted"), object: fileName)
//        }
//    }
    
    // Check if model exists
    func modelExists(name: String) -> Bool {
        let modelURL = modelDirectoryURL.appendingPathComponent("\(name).gguf")
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    // Safe model loading with error handling
    func loadModelWithErrorHandling(path: String) throws -> Model {
        // Check if file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw LocalModelError.modelNotFound
        }
        
        // Check file size
        let fileAttributes = try fileManager.attributesOfItem(atPath: path)
        guard let fileSize = fileAttributes[.size] as? UInt64, fileSize > 0 else {
            throw LocalModelError.failedToLoadModel
        }
        
        // Convert path to C string
        let pathCString = path.cString(using: .utf8)!
        
        // Set up model parameters
        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#endif
        
        // Attempt to load the model
        guard let model = llama_load_model_from_file(pathCString, modelParams) else {
            // Provide specific error messages based on file inspection
            if fileSize < 1024 * 1024 { // Less than 1MB
                throw LocalModelError.failedToLoadModel
            }
            
            // Check file extension
            if !path.lowercased().hasSuffix(".gguf") {
                throw LocalModelError.incompatibleModel
            }
            
            throw LocalModelError.failedToLoadModel
        }
        
        return model
    }
    
    // Initialize model if needed
    private func getOrCreateLlamaInstance(for modelName: String) throws -> LLM {
        if let instance = llamaInstances[modelName] {
            return instance
        }
        
        let modelURL = modelDirectoryURL.appendingPathComponent("\(modelName).gguf")
        
        if !FileManager.default.fileExists(atPath: modelURL.path) {
            throw LocalModelError.modelNotFound
        }
        
        do {
            // First try to load the model to check if it works
            _ = try loadModelWithErrorHandling(path: modelURL.path)
            
            // Create template based on prompt format
            let template = getTemplateForModel(modelName)
            
            // Initialize LLM with appropriate parameters
            let model = LLM(
                from: modelURL.path,
                stopSequence: template.stopSequence,
                history: [],
                seed: UInt32.random(in: .min ... .max),
                topK: 40,
                topP: 0.95,
                temp: 0.8,
                maxTokenCount: 2048
            )
            
            // Set the template
            model.template = template
            
            // Store the instance for reuse
            llamaInstances[modelName] = model
            return model
        } catch {
            print("Failed to initialize LLM for model \(modelName): \(error)")
            throw LocalModelError.failedToLoadModel
        }
    }
    
    // Get template for a model based on its name
    private func getTemplateForModel(_ modelName: String) -> Template {
        let modelInfo = LocalModelService.availableModels.first { $0.name == modelName }
        let modelNameLower = modelName.lowercased()
        
        // Detect model type based on name pattern
        if modelNameLower.contains("llama-3") || modelNameLower.contains("llama3") {
            return Template.chatML("You are a helpful assistant.")
        } else if modelNameLower.contains("gemma") {
            // Gemma 2 template
            return Template(
                user: ("<start_of_turn>user\n", "<end_of_turn>\n"),
                bot: ("<start_of_turn>model\n", "<end_of_turn>\n"),
                stopSequence: "<end_of_turn>",
                systemPrompt: "You are a helpful assistant."
            )
        } else if modelNameLower.contains("phi") {
            return Template(
                user: ("<|user|>\n", "\n"),
                bot: ("<|assistant|>\n", "\n"),
                stopSequence: "<|end|>",
                systemPrompt: "You are a helpful assistant."
            )
        } else if modelNameLower.contains("mistral") {
            return Template.mistral
        } else {
            // Default to a simple template that should work with most models
            return Template(
                user: ("USER: ", "\n"),
                bot: ("ASSISTANT: ", "\n\n"),
                stopSequence: "USER:",
                systemPrompt: "You are a helpful assistant."
            )
        }
    }
    
    // Convert OllamaKit messages to Chat objects
    private func convertToChatObjects(from messages: [OKChatRequestData.Message]) -> [Chat] {
        return messages.map { message in
            let role: Role = message.role == .user ? .user : .bot
            return Chat(role: role, content: message.content)
        }
    }
    
    // Generate a response from the model using llama.cpp
    func chat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        return Future<AnyPublisher<OKChatResponse, Error>, Error> { [weak self] promise in
            Task {
                do {
                    guard let self = self else {
                        throw LocalModelError.modelNotInitialized
                    }
                    
                    let llamaInstance = try self.getOrCreateLlamaInstance(for: data.model)
                    
                    // Extract system message if available
                    if let systemMessage = data.messages.first(where: { $0.role == .system }) {
                        if llamaInstance.template?.systemPrompt == nil {
                            // Create a new template with the system prompt
                            var template = llamaInstance.template
                            template?.systemPrompt = systemMessage.content
                            llamaInstance.template = template
                        }
                    }
                    
                    // Convert message history for context
                    let history = self.convertToChatObjects(from: data.messages)
                    llamaInstance.history = history
                    
                    // Get the latest user message
                    guard let lastUserMessage = data.messages.last(where: { $0.role == .user })?.content else {
                        throw LocalModelError.inferenceError("No user message found")
                    }
                    
                    // Set up a publisher to stream tokens
                    let subject = PassthroughSubject<OKChatResponse, Error>()
                    let publisher = subject.eraseToAnyPublisher()
                    
                    // Start inference
                    Task {
                        // Set up response handling
                        llamaInstance.update = { delta in
                            if let delta = delta {
                                // Create OKChatResponse from delta
                                let responseDict: [String: Any] = [
                                    "model": data.model,
                                    "message": [
                                        "role": "assistant",
                                        "content": TokenSanitizer.sanitize(token: delta)
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
                        
                        // Begin inference
                        await llamaInstance.respond(to: lastUserMessage)
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
    
    // Check if server is reachable (always returns true for local inference)
    func reachable() async -> Bool {
        return true
    }
}

// Model formats
enum ModelPromptFormat: String {
    case llama3
    case gemma
    case phi
    case mistral
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
}
