//
//  ChatsStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData
import OllamaKit
import Combine
import SwiftUI
import MLX

@Observable
final class ConversationStore: Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)
    
    var swiftDataService: SwiftDataService
    var generation: AnyCancellable?
    
    /// For some reason (SwiftUI bug / too frequent UI updates) updating UI for each stream message sometimes freezes the UI.
    /// Throttling UI updates seem to fix the issue.
    private var currentMessageBuffer: String = ""
#if os(macOS)
    private let throttler = Throttler(delay: 0.1)
#else
    private let throttler = Throttler(delay: 0.1)
#endif
    
    @MainActor var conversationState: ConversationState = .completed
    @MainActor var conversations: [ConversationSD] = []
    @MainActor var selectedConversation: ConversationSD?
    @MainActor var messages: [MessageSD] = []
    
    // MLX specific properties
    @MainActor private var useLocalInference: Bool {
        UserDefaults.standard.bool(forKey: "useLocalInference")
    }
    @MainActor private var selectedLocalModel: String {
        UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
    }
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    func loadConversations() async throws {
        print("loading conversations")
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.conversations = fetchedConversations
        }
        print("loaded conversations")
    }
    
    func deleteAllConversations() {
        Task {
            DispatchQueue.main.async { [weak self] in
                self?.messages = []
                self?.selectedConversation = nil
            }
            try? await swiftDataService.deleteConversations()
            try? await swiftDataService.deleteMessages()
            try? await loadConversations()
        }
    }
    
    func deleteDailyConversations(_ date: Date) {
        Task {
            DispatchQueue.main.async { [self] in
                selectedConversation = nil
                messages = []
            }
            try? await swiftDataService.deleteConversations()
            try? await loadConversations()
        }
    }
    
    func create(_ conversation: ConversationSD) async throws {
        try await swiftDataService.createConversation(conversation)
    }
    
    func reloadConversation(_ conversation: ConversationSD) async throws {
        let (messages, selectedConversation) = try await (
            swiftDataService.fetchMessages(conversation.id),
            swiftDataService.getConversation(conversation.id)
        )
        
        DispatchQueue.main.async {
            self.messages = messages
            self.selectedConversation = selectedConversation
        }
    }
    
    func selectConversation(_ conversation: ConversationSD) async throws {
        try await reloadConversation(conversation)
    }
    
    func delete(_ conversation: ConversationSD) async throws {
        try await swiftDataService.deleteConversation(conversation)
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.selectedConversation = nil
            self.conversations = fetchedConversations
        }
    }
    
    @MainActor func stopGenerate() {
        generation?.cancel()
        handleComplete()
        withAnimation {
            conversationState = .completed
        }
    }
    
    // Main method for sending prompts - uses the mixed backend
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, systemPrompt: String = "", trimmingMessageId: String? = nil) {
        sendPromptWithMixedBackend(
            userPrompt: userPrompt,
            model: model,
            image: image,
            systemPrompt: systemPrompt,
            trimmingMessageId: trimmingMessageId
        )
    }
    
    // Mixed backend implementation that handles both MLX and Ollama
    @MainActor
    func sendPromptWithMixedBackend(
        userPrompt: String,
        model: LanguageModelSD,
        image: Image? = nil,
        systemPrompt: String = "",
        trimmingMessageId: String? = nil
    ) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
        
        // Set up conversation
        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = model
        
        // Trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            conversation.messages = conversation.messages
                .sorted{$0.createdAt < $1.createdAt}
                .prefix(while: {$0.id.uuidString != trimmingMessageId})
        }
        
        // Add system prompt to very first message in the conversation
        if !systemPrompt.isEmpty && conversation.messages.isEmpty {
            let systemMessage = MessageSD(content: systemPrompt, role: "system")
            systemMessage.conversation = conversation
        }
        
        // Construct new message
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation
        
        // Prepare message history
        var messageHistory = conversation.messages
            .sorted{$0.createdAt < $1.createdAt}
            .map{OKChatRequestData.Message(role: OKChatRequestData.Message.Role(rawValue: $0.role) ?? .assistant, content: $0.content)}
        
        // Attach selected image to the last Message
        if let image = image?.render() {
            if let lastMessage = messageHistory.popLast() {
                let imagesBase64: [String] = [image.convertImageToBase64String()]
                let messageWithImage = OKChatRequestData.Message(role: lastMessage.role, content: lastMessage.content, images: imagesBase64)
                messageHistory.append(messageWithImage)
            }
        }
        
        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation
        
        conversationState = .loading
        
        Task {
            try await swiftDataService.updateConversation(conversation)
            try await swiftDataService.createMessage(userMessage)
            try await swiftDataService.createMessage(assistantMessage)
            try await reloadConversation(conversation)
            try? await loadConversations()
            
            // Determine which backend to use
            let isMLXModel = MLXIntegration.shared.isMLXModel(model.name)
            
            if model.modelProvider == .local && isMLXModel {
                // Use MLX backend
                handleMixedInference(model, messageHistory, useMLX: true)
            } else if model.modelProvider == .local {
                // Use llama.cpp backend (original implementation)
                handleMixedInference(model, messageHistory, useMLX: false)
            } else if await OllamaService.shared.reachable() {
                // Use Ollama for remote models
                handleOllamaInference(model, messageHistory)
            } else if useLocalInference {
                // Fall back to local inference if available
                if let localModel = await findAvailableLocalModel() {
                    // Update conversation to use local model
                    conversation.model = localModel
                    try? await swiftDataService.updateConversation(conversation)
                    
                    // Determine if it's an MLX model
                    let isMLXModel = MLXIntegration.shared.isMLXModel(localModel.name)
                    handleMixedInference(localModel, messageHistory, useMLX: isMLXModel)
                } else {
                    self.handleError("No local models available. Please download a model in Settings.")
                }
            } else {
                self.handleError("Model backend not available. Check your network connection or enable local inference.")
            }
        }
    }
    
    // Find an available local model
    @MainActor
    private func findAvailableLocalModel() async -> LanguageModelSD? {
        // Check if a specific local model is selected
        if !selectedLocalModel.isEmpty {
            // Try to find the selected model first
            if let selectedModel = LanguageModelStore.shared.models.first(where: { $0.name == selectedLocalModel }) {
                return selectedModel
            }
        }
        
        // First try MLX models
        let mlxModels = LanguageModelStore.shared.models.filter {
            $0.modelProvider == .local && $0.name.lowercased().contains("mlx")
        }
        
        if let firstMLXModel = mlxModels.first {
            // Update the selection
            UserDefaults.standard.set(firstMLXModel.name, forKey: "selectedLocalModel")
            return firstMLXModel
        }
        
        // Then try any local model
        let localModels = LanguageModelStore.shared.models.filter { $0.modelProvider == .local }
        
        if let firstLocalModel = localModels.first {
            // Update the selection
            UserDefaults.standard.set(firstLocalModel.name, forKey: "selectedLocalModel")
            return firstLocalModel
        }
        
        return nil
    }
    
    // Handle Ollama inference
    @MainActor
    func handleOllamaInference(_ model: LanguageModelSD, _ messageHistory: [OKChatRequestData.Message]) {
        DispatchQueue.global(qos: .background).async {
            var request = OKChatRequestData(model: model.name, messages: messageHistory)
            request.options = OKCompletionOptions(temperature: 0)
            
            self.generation = OllamaService.shared.ollamaKit.chat(data: request)
                .sink(receiveCompletion: { [weak self] completion in
                    switch completion {
                        case .finished:
                            self?.handleComplete()
                        case .failure(let error):
                            self?.handleError(error.localizedDescription)
                    }
                }, receiveValue: { [weak self] response in
                    self?.handleReceive(response)
                })
        }
    }
    
    // Handle inference with the appropriate backend
    @MainActor
    func handleMixedInference(
        _ model: LanguageModelSD,
        _ messageHistory: [OKChatRequestData.Message],
        useMLX: Bool
    ) {
        DispatchQueue.global(qos: .background).async {
            var request = OKChatRequestData(model: model.name, messages: messageHistory)
            request.options = OKCompletionOptions(temperature: 0)
            
            print("Sending request to \(useMLX ? "MLX" : "llama.cpp") model: \(model.name)")
            
            if useMLX {
                // Use MLX backend
                self.generation = MLXLocalModelService.shared.chat(data: request)
                    .sink(receiveCompletion: { [weak self] completion in
                        switch completion {
                            case .finished:
                                print("MLX inference completed successfully")
                                self?.handleComplete()
                            case .failure(let error):
                                print("MLX inference error: \(error.localizedDescription)")
                                self?.handleError(error.localizedDescription)
                        }
                    }, receiveValue: { [weak self] response in
                        self?.handleReceive(response)
                    })
//            } else if let localModelService = MLXLocalModelService.shared {
//                // Use llama.cpp backend
//                self.generation = localModelService.chat(data: request)
//                    .sink(receiveCompletion: { [weak self] completion in
//                        switch completion {
//                            case .finished:
//                                print("llama.cpp inference completed successfully")
//                                self?.handleComplete()
//                            case .failure(let error):
//                                print("llama.cpp inference error: \(error.localizedDescription)")
//                                self?.handleError(error.localizedDescription)
//                        }
//                    }, receiveValue: { [weak self] response in
//                        self?.handleReceive(response)
//                    })
            } else {
                // No local model service available
                DispatchQueue.main.async {
                    self.handleError("Local inference service not available")
                }
            }
        }
    }
    
    @MainActor
    func handleReceive(_ response: OKChatResponse)  {
        if messages.isEmpty { return }
        
        if let responseContent = response.message?.content {
            currentMessageBuffer = currentMessageBuffer + responseContent
            
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                let lastIndex = self.messages.count - 1
                self.messages[lastIndex].content.append(currentMessageBuffer)
                currentMessageBuffer = ""
            }
        }
    }
    
    @MainActor
    func handleError(_ errorMessage: String) {
        guard let lastMesasge = messages.last else { return }
        lastMesasge.error = true
        lastMesasge.done = false
        
        Task(priority: .background) {
            try? await swiftDataService.updateMessage(lastMesasge)
        }
        
        withAnimation {
            conversationState = .error(message: errorMessage)
        }
    }
    
    @MainActor
    func handleComplete() {
        guard let lastMesasge = messages.last else { return }
        lastMesasge.error = false
        lastMesasge.done = true
        
        Task(priority: .background) {
            try await self.swiftDataService.updateMessage(lastMesasge)
        }
        
        withAnimation {
            conversationState = .completed
        }
    }
}
