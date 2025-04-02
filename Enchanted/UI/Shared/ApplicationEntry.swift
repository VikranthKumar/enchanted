//
//  ApplicationEntry.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 12/02/2024.
//

import SwiftUI
import SwiftData

struct ApplicationEntry: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @State private var languageModelStore = LanguageModelStore.shared
    @State private var conversationStore = ConversationStore.shared
    @State private var completionsStore = CompletionsStore.shared
    @State private var appStore = AppStore.shared
    @State private var isInitializing = true // Add this state
    
    var body: some View {
        ZStack {
            VStack {
                switch appStore.appState {
                    case .chat:
                        SharedChatView(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
                    case .voice:
                        Voice(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
                }
            }
            
            // Add a loading overlay during initialization
            if isInitializing {
                Color(.gray)
                    .opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Text("Initializing...")
                        .font(.headline)
                    
                    ProgressView()
                        .padding()
                    
                    Text("Loading models and conversations")
                        .font(.caption)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
        }
        .task {
            print("Application starting up")
            
            // Show the initializing overlay
            isInitializing = true
            
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                print("Bundle Identifier: \(bundleIdentifier)")
            } else {
                print("Bundle Identifier not found.")
            }
            
            // Check local inference settings
            let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
            print("Local inference enabled: \(useLocalInference)")
            
            // Initialize model store first
            await LocalModelService.shared.initializeModels()
            await languageModelStore.initialize()
            
            // Then load conversations
            try? await conversationStore.loadConversations()
            
            // Load completions
            completionsStore.load()
            
            // Hide the loading overlay
            DispatchQueue.main.async {
                isInitializing = false
            }
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
    }
}

