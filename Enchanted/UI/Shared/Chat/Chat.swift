//
//  MainView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//

import SwiftUI

struct SharedChatView: View, Sendable {
    @State private var languageModelStore: LanguageModelStore
    @State private var conversationStore: ConversationStore
    @State private var appStore: AppStore
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @AppStorage("appUserInitials") private var userInitials: String = ""
    @AppStorage("defaultOllamaModel") private var defaultOllamaModel: String = ""
    @State var showMenu = false
    
    init(languageModelStore: LanguageModelStore, conversationStore: ConversationStore, appStore: AppStore) {
        _languageModelStore = State(initialValue: languageModelStore)
        _conversationStore = State(initialValue: conversationStore)
        _appStore = State(initialValue: appStore)
    }
    
    func toggleMenu() {
        withAnimation(.spring) {
            showMenu.toggle()
        }
        Task {
            await Haptics.shared.mediumTap()
        }
    }
    
    @MainActor
    func updateSelectedModel() {
        print("Updating selected model. Current model: \(languageModelStore.selectedModel?.name ?? "none")")
        print("Available models: \(languageModelStore.models.map { $0.name }.joined(separator: ", "))")
        
        // Check if we have a selected model
        if languageModelStore.selectedModel == nil {
            // Try to select a model based on settings
            let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
            
            if useLocalInference {
                // Try to select a local model
                let selectedLocalModel = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
                
                if !selectedLocalModel.isEmpty {
                    languageModelStore.setModel(modelName: selectedLocalModel)
                    print("Set model to selected local model: \(selectedLocalModel)")
                } else if let firstLocalModel = languageModelStore.models.first(where: { $0.modelProvider == .local }) {
                    languageModelStore.setModel(model: firstLocalModel)
                    print("Set model to first local model: \(firstLocalModel.name)")
                }
            } else {
                // Try to select an Ollama model
                if defaultOllamaModel != "" {
                    languageModelStore.setModel(modelName: defaultOllamaModel)
                    print("Set model to default Ollama model: \(defaultOllamaModel)")
                } else if let firstModel = languageModelStore.models.first {
                    languageModelStore.setModel(model: firstModel)
                    print("Set model to first available model: \(firstModel.name)")
                }
            }
        }
        
        print("Selected model after update: \(languageModelStore.selectedModel?.name ?? "none")")
    }
    
    // Check if we have valid models before sending message
    @MainActor
    func sendMessage(prompt: String, model: LanguageModelSD?, image: Image?, trimmingMessageId: String?) {
        // Verify we have a model
        guard let modelToUse = model ?? languageModelStore.selectedModel else {
            print("ERROR: No model available to send message")
            return
        }
        
        print("Sending message with model: \(modelToUse.name), provider: \(modelToUse.modelProvider?.rawValue ?? "unknown")")
        
        conversationStore.sendPrompt(
            userPrompt: prompt,
            model: modelToUse,
            image: image,
            systemPrompt: systemPrompt,
            trimmingMessageId: trimmingMessageId
        )
    }
    
    func onConversationTap(_ conversation: ConversationSD) {
        Task {
            try await conversationStore.selectConversation(conversation)
            await languageModelStore.setModel(model: conversation.model)
            Haptics.shared.mediumTap()
        }
        withAnimation {
            showMenu.toggle()
        }
    }
    
    @MainActor func onStopGenerateTap() {
        conversationStore.stopGenerate()
        Haptics.shared.mediumTap()
    }
    
    func onConversationDelete(_ conversation: ConversationSD) {
        Task {
            await Haptics.shared.mediumTap()
            try? await conversationStore.delete(conversation)
        }
    }
    
    func newConversation() {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.3)) {
                self.conversationStore.selectedConversation = nil
            }
        }
        
        Task {
            await Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
        }
        
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }
    
    func copyChat(_ json: Bool) {
        Task {
            let messages = await ConversationStore.shared.messages
            
            if messages.count == 0 {
                return
            }
            
            if json {
                let jsonArray = messages.map { message in
                    return [
                        "role": message.role,
                        "content": message.content
                    ]
                }
                let jsonEncoder = JSONEncoder()
                jsonEncoder.outputFormatting = [.withoutEscapingSlashes]

                if let jsonData = try? jsonEncoder.encode(jsonArray),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    Clipboard.shared.setString(jsonString)
                }
            } else {
                let body = messages.map{"\($0.role.capitalized): \($0.content)"}.joined(separator: "\n\n")
                Clipboard.shared.setString(body)
            }
        }
    }
    
    var body: some View {
        Group {
#if os(macOS) || os(visionOS)
            ChatView(
                selectedConversation: conversationStore.selectedConversation,
                conversations: conversationStore.conversations,
                messages: conversationStore.messages,
                modelsList: languageModelStore.models,
                onMenuTap: toggleMenu,
                onNewConversationTap: newConversation,
                onSendMessageTap: sendMessage,
                onConversationTap:onConversationTap,
                conversationState: conversationStore.conversationState,
                onStopGenerateTap: onStopGenerateTap,
                reachable: appStore.isReachable,
                modelSupportsImages: languageModelStore.supportsImages,
                selectedModel: languageModelStore.selectedModel,
                onSelectModel: languageModelStore.setModel,
                onConversationDelete: onConversationDelete,
                onDeleteDailyConversations: conversationStore.deleteDailyConversations,
                userInitials: userInitials,
                copyChat: copyChat
            )
#else
            SideBarStack(sidebarWidth: 300,showSidebar: $showMenu, sidebar: {
                SidebarView(
                    selectedConversation: conversationStore.selectedConversation,
                    conversations: conversationStore.conversations,
                    onConversationTap: onConversationTap,
                    onConversationDelete: onConversationDelete,
                    onDeleteDailyConversations: conversationStore.deleteDailyConversations
                )
            }) {
                ChatView(
                    conversation: conversationStore.selectedConversation,
                    messages: conversationStore.messages,
                    modelsList: languageModelStore.models,
                    selectedModel: languageModelStore.selectedModel,
                    onSelectModel: languageModelStore.setModel,
                    onMenuTap: toggleMenu,
                    onNewConversationTap: newConversation,
                    onSendMessageTap: sendMessage,
                    conversationState: conversationStore.conversationState,
                    onStopGenerateTap: onStopGenerateTap,
                    reachable: appStore.isReachable,
                    modelSupportsImages: languageModelStore.supportsImages,
                    userInitials: userInitials
                )
            }
#endif
        }
        .onChange(of: languageModelStore.models, { _, modelsList in
            if languageModelStore.selectedModel == nil {
                updateSelectedModel()
            }
        })
        .onChange(of: conversationStore.selectedConversation, initial: true, { _, newConversation in
            if let conversation = newConversation {
                languageModelStore.setModel(model: conversation.model)
            } else {
                updateSelectedModel()
            }
        })
    }
}
