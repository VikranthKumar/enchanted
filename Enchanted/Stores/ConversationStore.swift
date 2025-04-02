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

@Observable
final class ConversationStore: Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    private var generation: AnyCancellable?
    
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
    // Add this property to ConversationStore
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
    
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, systemPrompt: String = "", trimmingMessageId: String? = nil) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }
        
        // Determine appropriate model based on inference preference
        var selectedModel = model
        
        // If local inference is enabled, but an Ollama model is selected, try to find a local model
        if useLocalInference && model.modelProvider != .local {
            if let localModel = LanguageModelStore.shared.models.first(where: { $0.modelProvider == .local }) {
                selectedModel = localModel
            }
        }
        
        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = selectedModel
        
        // trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            conversation.messages = conversation.messages
                .sorted{$0.createdAt < $1.createdAt}
                .prefix(while: {$0.id.uuidString != trimmingMessageId})
        }
        
        // add system prompt to very first message in the conversation
        if !systemPrompt.isEmpty && conversation.messages.isEmpty {
            let systemMessage = MessageSD(content: systemPrompt, role: "system")
            systemMessage.conversation = conversation
        }
        
        // construct new message
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation
        
        // prepare message history
        var messageHistory = conversation.messages
            .sorted{$0.createdAt < $1.createdAt}
            .map{OKChatRequestData.Message(role: OKChatRequestData.Message.Role(rawValue: $0.role) ?? .assistant, content: $0.content)}
        
        // attach selected image to the last Message
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
            
            // Determine which service to use based on model provider
            if selectedModel.modelProvider == .local {
                // Always use local service if model is local
                handleLocalInference(selectedModel, messageHistory)
            } else if await OllamaService.shared.reachable() {
                // Use Ollama if server is reachable
                handleOllamaInference(selectedModel, messageHistory)
            } else if useLocalInference {
                // Fall back to local inference if Ollama unreachable but local is enabled
                if let localModel = await findAvailableLocalModel() {
                    // Update conversation to use local model
                    conversation.model = localModel
                    try? await swiftDataService.updateConversation(conversation)
                    handleLocalInference(localModel, messageHistory)
                } else {
                    self.handleError("No local models available. Please download a model in Settings.")
                }
            } else {
                self.handleError("Ollama server unreachable")
            }
        }
    }
    
    @MainActor
    private func findAvailableLocalModel() async -> LanguageModelSD? {
        // Check if a specific local model is selected
        if !selectedLocalModel.isEmpty {
            // Try to find the selected model first
            if let selectedModel = LanguageModelStore.shared.models.first(where: { $0.name == selectedLocalModel }) {
                return selectedModel
            }
        }
        
        // Check if any local models are available as fallback
        let localModels = try? await LocalModelService.shared.getModels()
        if let localModels = localModels, !localModels.isEmpty {
            // If we have models but not the selected one, update the selection
            let localModelName = localModels.first!.name
            UserDefaults.standard.set(localModelName, forKey: "selectedLocalModel")
            
            // Find the corresponding LanguageModelSD
            return LanguageModelStore.shared.models.first(where: { $0.name == localModelName })
        }
        
        return nil
    }
    
    @MainActor
    private func handleLocalInference(_ model: LanguageModelSD, _ messageHistory: [OKChatRequestData.Message]) {
        DispatchQueue.global(qos: .background).async {
            var request = OKChatRequestData(model: model.name, messages: messageHistory)
            request.options = OKCompletionOptions(temperature: 0)
            
            self.generation = LocalModelService.shared.chat(data: request)
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
    
    @MainActor
    private func handleOllamaInference(_ model: LanguageModelSD, _ messageHistory: [OKChatRequestData.Message]) {
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
    
    @MainActor
    private func handleReceive(_ response: OKChatResponse)  {
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
    private func handleError(_ errorMessage: String) {
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
    private func handleComplete() {
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
