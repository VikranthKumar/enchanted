//
//  SettingsView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @AppStorage("ollamaUri") private var ollamaUri: String = "http://localhost:11434"
    @AppStorage("ollamaBearerToken") private var ollamaBearerToken: String = ""
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @AppStorage("menuBarIcon") private var menuBarIcon: String = "brain.head.profile"
    @AppStorage("vibrations") private var vibrations: Bool = true
    @AppStorage("useLocalInference") private var useLocalInference: Bool = false
    @AppStorage("showBothBackends") private var showBothBackends: Bool = false
    @AppStorage("appUserInitials") private var userInitials: String = ""
    @AppStorage("defaultOllamaModel") private var defaultOllamaModel: String = ""
    @AppStorage("autoSaveConversations") private var autoSaveConversations: Bool = true
    @AppStorage("pingInterval") private var pingInterval: String = "5"
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    
    @State private var isOllmaReachable = false
    @State private var isMLXEnabled = false
    @State private var showMLXModelsSheet = false
    @State private var localModelsCount = 0
    @State private var voiceIdentifier: String = UserDefaults.standard.string(forKey: "voiceIdentifier") ?? ""
    @StateObject private var speechSynthesizer = SpeechSynthesizer.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section(header: Text("App Settings")) {
                    Picker("Appearance", selection: $colorScheme) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.toString)
                                .tag(scheme)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Inference Mode
                    Picker("Inference Mode", selection: $useLocalInference) {
                        Text("Ollama").tag(false)
                        Text("Local").tag(true)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: useLocalInference) { _, newValue in
                        Task {
                            await refreshModels()
                        }
                    }
                    
                    Toggle("Show Both Backends", isOn: $showBothBackends)
                        .onChange(of: showBothBackends) { _, _ in
                            Task {
                                await refreshModels()
                            }
                        }
                    
                    TextField("Your Initials", text: $userInitials)
                        .onChange(of: userInitials) { _, newValue in
                            if newValue.count > 2 {
                                userInitials = String(newValue.prefix(2))
                            }
                        }
                }
                
                // Local Inference Section
                if useLocalInference {
                    Section(header: Text("Local Inference")) {
                        HStack {
                            Text("Local Models")
                            Spacer()
                            Text("\(localModelsCount) models installed")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Manage MLX Models") {
                            showMLXModelsSheet = true
                        }
                        
                        // Status indicator
                        HStack {
                            Text("MLX Status")
                            Spacer()
                            Text(isMLXEnabled ? "Available" : "Not Available")
                                .foregroundColor(isMLXEnabled ? .green : .red)
                        }
                        
                        // Explanation text
                        Text("Local inference uses MLX to run models directly on your device without sending data to external servers. Models need to be downloaded before they can be used.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Ollama Section (always show, but with different content if local inference is enabled)
                Section(header: Text("Ollama Settings")) {
                    if !useLocalInference {
                        TextField("Server endpoint", text: $ollamaUri)
                        TextField("Bearer Token (optional)", text: $ollamaBearerToken)
                        
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(isOllmaReachable ? "Reachable" : "Unreachable")
                                .foregroundColor(isOllmaReachable ? .green : .red)
                        }
                    } else {
                        Text("Ollama settings are disabled when using local inference. Switch inference mode to Ollama to configure these settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Voice")) {
                    Picker("Voice", selection: $voiceIdentifier) {
                        ForEach(speechSynthesizer.voices.sorted(by: { $0.name < $1.name }), id: \.identifier) { voice in
                            Text(voice.prettyName).tag(voice.identifier)
                        }
                    }
                    .onChange(of: voiceIdentifier) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "voiceIdentifier")
                    }
                    
#if os(iOS)
                    Toggle("Vibrations", isOn: $vibrations)
#endif
                }
                
                Section(header: Text("System Prompt")) {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("Advanced")) {
                    TextField("Ping interval (seconds)", text: $pingInterval)
                        .keyboardType(.numberPad)
                    
                    Toggle("Auto-save conversations", isOn: $autoSaveConversations)
                    
#if os(macOS)
                    HStack {
                        Text("Menu bar icon")
                        Spacer()
                        Picker("", selection: $menuBarIcon) {
                            Image(systemName: "brain.head.profile").tag("brain.head.profile")
                            Image(systemName: "sparkles").tag("sparkles")
                            Image(systemName: "wand.and.stars").tag("wand.and.stars")
                            Image(systemName: "wand.and.rays").tag("wand.and.rays")
                            Image(systemName: "lock").tag("lock")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                    }
#endif
                    
                    Button("Reset Settings") {
                        resetSettings()
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.4")
                    }
                    
                    HStack {
                        Text("Ollama Library")
                        Spacer()
                        Text("v0.0.1")
                    }
                    
                    HStack {
                        Text("MLX Library")
                        Spacer()
                        Text("v0.0.9")
                    }
                    
                    Link("GitHub Repository", destination: URL(string: "https://github.com/AugustDev/enchanted")!)
                }
            }
        }
        .onAppear {
            // Check API reachability
            Task {
                isOllmaReachable = await OllamaService.shared.reachable()
                
                // Check MLX availability
                isMLXEnabled = true // MLX is always available if compiled in
                
                // Count local models
                do {
                    let models = try await MLXLocalModelService.shared.getModels()
                    localModelsCount = models.count
                } catch {
                    print("Error counting local models: \(error)")
                    localModelsCount = 0
                }
            }
        }
        .sheet(isPresented: $showMLXModelsSheet) {
            MLXModelsView()
                .modifier(MLXSheetSizeModifier())
                .onDisappear {
                    Task {
                        // Get updated model count
                        do {
                            let models = try await MLXLocalModelService.shared.getModels()
                            localModelsCount = models.count
                        } catch {
                            print("Error counting local models: \(error)")
                            localModelsCount = 0
                        }
                    }
                }
        }
    }
    
    // Reset settings to default values
    private func resetSettings() {
        colorScheme = .system
        ollamaUri = "http://localhost:11434"
        ollamaBearerToken = ""
        systemPrompt = ""
        menuBarIcon = "brain.head.profile"
        vibrations = true
        useLocalInference = false
        showBothBackends = false
        userInitials = ""
        defaultOllamaModel = ""
        autoSaveConversations = true
        pingInterval = "5"
    }
    
    // Refresh models
    private func refreshModels() async {
        await LanguageModelStore.shared.refreshModelsWithMLX()
        
        // Get updated model count
        do {
            let models = try await MLXLocalModelService.shared.getModels()
            localModelsCount = models.count
        } catch {
            print("Error counting local models: \(error)")
            localModelsCount = 0
        }
    }
}

#Preview {
    SettingsView()
}
