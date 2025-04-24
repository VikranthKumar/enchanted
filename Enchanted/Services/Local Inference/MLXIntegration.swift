//
//  MLXIntegration.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/23/25.
//

import Foundation
import SwiftUI
import Combine
import OllamaKit

/// Helper for integrating MLX into the Enchanted app
class MLXIntegration {
    // Singleton instance
    static let shared = MLXIntegration()
    
    /// Initialize MLX and Ollama local models
    func initializeMixedModels(languageModelStore: LanguageModelStore) async {
        print("Initializing mixed models (MLX and Ollama)")
        
        // Initialize MLX models
        await MLXLocalModelService.shared.initializeModels()
        
        // Initialize Ollama models
        if await OllamaService.shared.reachable() {
            do {
                let ollamaModels = try await OllamaService.shared.getModels()
                print("Found \(ollamaModels.count) Ollama models")
            } catch {
                print("Failed to get Ollama models: \(error)")
            }
        } else {
            print("Ollama service not reachable")
        }
        
        // Update the model store
        await languageModelStore.refreshModelsWithMLX()
    }
    
    /// Get models from both MLX and Ollama
    func getMixedModels() async throws -> [LanguageModel] {
        var models: [LanguageModel] = []
        
        // Get MLX models
        do {
            let mlxModels = try await MLXLocalModelService.shared.getModels()
            models.append(contentsOf: mlxModels)
            print("Found \(mlxModels.count) MLX models")
        } catch {
            print("Error getting MLX models: \(error)")
        }
        
        // Get Ollama models if reachable
        if await OllamaService.shared.reachable() {
            do {
                let ollamaModels = try await OllamaService.shared.getModels()
                models.append(contentsOf: ollamaModels)
                print("Found \(ollamaModels.count) Ollama models")
            } catch {
                print("Error getting Ollama models: \(error)")
            }
        }
        
        return models
    }
    
    /// Chat with mixed backend (MLX or Ollama)
    func mixedChat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        // Check if this is an MLX model
        let modelName = data.model
        
        if modelName.lowercased().contains("mlx") {
            // Use MLX backend
            print("Using MLX backend for model: \(modelName)")
            return MLXLocalModelService.shared.chat(data: data)
        } else {
            // Use Ollama backend
            print("Using Ollama backend for model: \(modelName)")
            return OllamaService.shared.ollamaKit.chat(data: data)
        }
    }
    
    /// Check if API is reachable (either MLX or Ollama)
    func mixedReachable() async -> Bool {
        // MLX is always reachable since it's local
        let mlxReachable = true
        
        // Check if Ollama is reachable
        let ollamaReachable = await OllamaService.shared.reachable()
        
        // If either is reachable, we can serve requests
        return mlxReachable || ollamaReachable
    }
    
    /// Determine if model exists locally in MLX
    func isMLXModel(_ modelName: String) -> Bool {
        return modelName.lowercased().contains("mlx")
    }
}

// MARK: - LanguageModelStore Extensions

extension LanguageModelStore {
    /// Refresh models including MLX models
//    @MainActor
//    func refreshModelsWithMLX() async {
//        print("Refreshing models with MLX")
//        
//        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
//        print("Local inference enabled: \(useLocalInference)")
//        
//        // Get MLX models
//        var mlxModels: [LanguageModelSD] = []
//        
//        do {
//            let localMLXModels = try await MLXLocalModelService.shared.getModels()
//            mlxModels = localMLXModels.map {
//                LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .local)
//            }
//            print("Found \(mlxModels.count) MLX models")
//        } catch {
//            print("Error fetching MLX models: \(error)")
//        }
//        
//        // Get Ollama models if not using local inference
//        var ollamaModels: [LanguageModelSD] = []
//        
//        let ollamaRecable = await OllamaService.shared.reachable()
//        
//        if !useLocalInference && ollamaRecable {
//            do {
//                let remoteModels = try await OllamaService.shared.getModels()
//                ollamaModels = remoteModels.map {
//                    LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .ollama)
//                }
//                print("Found \(ollamaModels.count) Ollama models")
//            } catch {
//                print("Error fetching Ollama models: \(error)")
//            }
//        }
//        
//        // Combine models
//        let combinedModels = mlxModels + ollamaModels
//        
//        // Save models to SwiftData
//        if !combinedModels.isEmpty {
//            do {
//                // First clear existing models
//                try await deleteAllModels()
//                
//                // Then save new models
//                try await swiftDataService.saveModels(models: combinedModels)
//                
//                // Fetch and update models
//                models = try await swiftDataService.fetchModels()
//                
//                // Select appropriate model
//                selectAppropriateModel()
//            } catch {
//                print("Error saving models: \(error)")
//            }
//        }
//    }
    
    /// Select the appropriate model based on settings
    @MainActor
    private func selectAppropriateModel() {
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        let selectedLocalModelName = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
        let defaultOllamaModel = UserDefaults.standard.string(forKey: "defaultOllamaModel") ?? ""
        
        if useLocalInference {
            // Try to find the selected local model
            if !selectedLocalModelName.isEmpty,
               let localModel = models.first(where: { $0.name == selectedLocalModelName && $0.modelProvider == .local }) {
                selectedModel = localModel
                return
            }
            
            // Try to find any MLX model
            if let mlxModel = models.first(where: { $0.name.lowercased().contains("mlx") && $0.modelProvider == .local }) {
                selectedModel = mlxModel
                // Update selected model name
                UserDefaults.standard.set(mlxModel.name, forKey: "selectedLocalModel")
                return
            }
            
            // Try to find any local model
            if let localModel = models.first(where: { $0.modelProvider == .local }) {
                selectedModel = localModel
                // Update selected model name
                UserDefaults.standard.set(localModel.name, forKey: "selectedLocalModel")
                return
            }
        }
        
        // Fall back to Ollama model
        if !defaultOllamaModel.isEmpty,
           let ollamaModel = models.first(where: { $0.name == defaultOllamaModel && $0.modelProvider == .ollama }) {
            selectedModel = ollamaModel
        } else if let firstOllamaModel = models.first(where: { $0.modelProvider == .ollama }) {
            selectedModel = firstOllamaModel
        }
    }
}

// MARK: - ConversationStore Extensions

extension ConversationStore {
    /// Send prompt with mixed backend (MLX or Ollama)
//    @MainActor
//    func sendPromptWithMixedBackend(
//        userPrompt: String,
//        model: LanguageModelSD,
//        image: Image? = nil,
//        systemPrompt: String = "",
//        trimmingMessageId: String? = nil
//    ) {
//        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
//        
//        // Set up conversation
//        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
//        conversation.updatedAt = Date.now
//        conversation.model = model
//        
//        // Trim conversation if on edit mode
//        if let trimmingMessageId = trimmingMessageId {
//            conversation.messages = conversation.messages
//                .sorted{$0.createdAt < $1.createdAt}
//                .prefix(while: {$0.id.uuidString != trimmingMessageId})
//        }
//        
//        // Add system prompt to very first message in the conversation
//        if !systemPrompt.isEmpty && conversation.messages.isEmpty {
//            let systemMessage = MessageSD(content: systemPrompt, role: "system")
//            systemMessage.conversation = conversation
//        }
//        
//        // Construct new message
//        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
//        userMessage.conversation = conversation
//        
//        // Prepare message history
//        var messageHistory = conversation.messages
//            .sorted{$0.createdAt < $1.createdAt}
//            .map{OKChatRequestData.Message(role: OKChatRequestData.Message.Role(rawValue: $0.role) ?? .assistant, content: $0.content)}
//        
//        // Attach selected image to the last Message
//        if let image = image?.render() {
//            if let lastMessage = messageHistory.popLast() {
//                let imagesBase64: [String] = [image.convertImageToBase64String()]
//                let messageWithImage = OKChatRequestData.Message(role: lastMessage.role, content: lastMessage.content, images: imagesBase64)
//                messageHistory.append(messageWithImage)
//            }
//        }
//        
//        let assistantMessage = MessageSD(content: "", role: "assistant")
//        assistantMessage.conversation = conversation
//        
//        conversationState = .loading
//        
//        Task {
//            try await swiftDataService.updateConversation(conversation)
//            try await swiftDataService.createMessage(userMessage)
//            try await swiftDataService.createMessage(assistantMessage)
//            try await reloadConversation(conversation)
//            try? await loadConversations()
//            
//            // Determine which backend to use
//            let isMLXModel = MLXIntegration.shared.isMLXModel(model.name)
//            
//            if model.modelProvider == .local && isMLXModel {
//                // Use MLX backend
//                handleMixedInference(model, messageHistory, useMLX: true)
//            } else if model.modelProvider == .local {
//                // Use llama.cpp backend
//                handleMixedInference(model, messageHistory, useMLX: false)
//            } else if await OllamaService.shared.reachable() {
//                // Use Ollama for remote models
//                handleOllamaInference(model, messageHistory)
//            } else {
//                self.handleError("Model backend not available")
//            }
//        }
//    }
    
    /// Handle inference with the appropriate backend
//    @MainActor
//    private func handleMixedInference(
//        _ model: LanguageModelSD,
//        _ messageHistory: [OKChatRequestData.Message],
//        useMLX: Bool
//    ) {
//        DispatchQueue.global(qos: .background).async {
//            var request = OKChatRequestData(model: model.name, messages: messageHistory)
//            request.options = OKCompletionOptions(temperature: 0)
//            
//            print("Sending request to \(useMLX ? "MLX" : "Ollama") model: \(model.name)")
//            
//            if useMLX {
//                // Use MLX backend
//                self.generation = MLXLocalModelService.shared.chat(data: request)
//                    .sink(receiveCompletion: { [weak self] completion in
//                        switch completion {
//                            case .finished:
//                                print("MLX inference completed successfully")
//                                self?.handleComplete()
//                            case .failure(let error):
//                                print("MLX inference error: \(error.localizedDescription)")
//                                self?.handleError(error.localizedDescription)
//                        }
//                    }, receiveValue: { [weak self] response in
//                        self?.handleReceive(response)
//                    })
//            } else {
//                // Use Ollama backend
//                self.generation = OllamaService.shared.ollamaKit.chat(data: request)
//                    .sink(receiveCompletion: { [weak self] completion in
//                        switch completion {
//                            case .finished:
//                                print("Ollama inference completed successfully")
//                                self?.handleComplete()
//                            case .failure(let error):
//                                print("Ollama inference error: \(error.localizedDescription)")
//                                self?.handleError(error.localizedDescription)
//                        }
//                    }, receiveValue: { [weak self] response in
//                        self?.handleReceive(response)
//                    })
//            }
//        }
//    }
}
