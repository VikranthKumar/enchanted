//
//  SettingsView.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var ollamaUri: String
    @Binding var systemPrompt: String
    @Binding var vibrations: Bool
    @Binding var colorScheme: AppColorScheme
    @Binding var defaultOllamModel: String
    @Binding var ollamaBearerToken: String
    @Binding var appUserInitials: String
    @Binding var pingInterval: String
    @Binding var voiceIdentifier: String
    @State var ollamaStatus: Bool?
    var save: () -> ()
    var checkServer: () -> ()
    var deleteAll: () -> ()
    var ollamaLangugeModels: [LanguageModelSD]
    var voices: [AVSpeechSynthesisVoice]
    
    @State private var deleteConversationsDialog = false
    @AppStorage("useLocalInference") private var useLocalInference: Bool = false
    @State private var showLocalModelsSheet = false
    @State private var downloadedModelsCount: Int = 0
    @AppStorage("selectedLocalModel") private var selectedLocalModel: String = ""

    
    func updateDownloadedModelsCount() {
        Task {
            if useLocalInference {
                let models = try? await LocalModelService.shared.getModels()
                DispatchQueue.main.async {
                    downloadedModelsCount = models?.count ?? 0
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                    
                    
                    Spacer()
                    
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                }
                
                HStack {
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
            }
            .padding()
            
            Form {
                Section(header: Text("LOCAL INFERENCE").font(.headline).padding(.top, 20)) {
                    Toggle(isOn: $useLocalInference.onChange { newValue in
                        if newValue {
                            updateDownloadedModelsCount()
                            selectLocalModel() // Auto-select a local model
                        }
                    }, label: {
                        Label("Use Local Inference", systemImage: "cpu")
                            .foregroundStyle(Color.label)
                    })
                    
                    Button(action: { showLocalModelsSheet.toggle() }) {
                        HStack {
                            Label("Manage Local Models", systemImage: "square.and.arrow.down")
                                .foregroundStyle(Color.label)
                            
                            Spacer()
                            
                            if downloadedModelsCount > 0 {
                                Text("\(downloadedModelsCount) models")
                                    .foregroundColor(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    .disabled(!useLocalInference)
                    .sheet(isPresented: $showLocalModelsSheet) {
                        LocalModelsView()
                    }
                    
                    if useLocalInference {
                        Text("Models will run directly on your device without requiring an Ollama server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Enables running LLMs directly on this device without requiring an Ollama server")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Ollama").font(.headline)) {
                    
                    TextField("Ollama server URI", text: $ollamaUri, onCommit: checkServer)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                        .padding(.top, 8)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    
                    VStack(alignment: .leading) {
                        Text("System prompt")
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 13))
                            .cornerRadius(4)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                    }
                    
                    Picker(selection: $defaultOllamModel) {
                        ForEach(ollamaLangugeModels, id:\.self) { model in
                            Text(model.name).tag(model.name)
                        }
                    } label: {
                        Label {
                            Text("Default Model")
                        } icon: {
                            Image("ollama")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color(.label))
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    
                    TextField("Bearer Token", text: $ollamaBearerToken)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .autocapitalization(.none)
#endif
                    TextField("Ping Interval (seconds)", text: $pingInterval)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Section(header: Text("APP").font(.headline).padding(.top, 20)) {
                        
#if os(iOS)
                        Toggle(isOn: $vibrations, label: {
                            Label("Vibrations", systemImage: "water.waves")
                                .foregroundStyle(Color.label)
                        })
#endif
                    }
                    
                    
                    Picker(selection: $colorScheme) {
                        ForEach(AppColorScheme.allCases, id:\.self) { scheme in
                            Text(scheme.toString).tag(scheme.id)
                        }
                    } label: {
                        Label("Appearance", systemImage: "sun.max")
                            .foregroundStyle(Color.label)
                    }
                    
                    Picker(selection: $voiceIdentifier) {
                        ForEach(voices, id:\.self.identifier) { voice in
                            Text(voice.prettyName).tag(voice.identifier)
                        }
                    } label: {
                        Label("Voice", systemImage: "waveform")
                            .foregroundStyle(Color.label)
                        
#if os(macOS)
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > System Voice > Manage Voices.")
#else
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > Voices.")
#endif
                        
                        Button(action: {
#if os(macOS)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems") {
                                NSWorkspace.shared.open(url)
                            }
#else
                            let url = URL(string: "App-Prefs:root=General&path=ACCESSIBILITY")
                            if let url = url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
#endif
                            
                        }) {
                            
                            Text("Open Settings")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    
                    TextField("Initials", text: $appUserInitials)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    
                    Button(action: {deleteConversationsDialog.toggle()}) {
                        HStack {
                            Spacer()
                            
                            Text("Clear All Data")
                                .foregroundStyle(Color(.systemRed))
                                .padding(.vertical, 6)
                            
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
        .confirmationDialog("Delete All Conversations?", isPresented: $deleteConversationsDialog) {
            Button("Delete", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete All Conversations?")
        }
        .onAppear {
            updateDownloadedModelsCount()
            if useLocalInference && LanguageModelStore.shared.selectedModel?.modelProvider != .local {
                selectLocalModel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LocalModelSelected"))) { _ in
            updateDownloadedModelsCount()
        }
    }
    
    func selectLocalModel() {
        Task {
            let models = try? await LocalModelService.shared.getModels()
            DispatchQueue.main.async {
                if let firstModel = models?.first {
                    print("Auto-selecting local model: \(firstModel.name)")
                    selectedLocalModel = firstModel.name
                    
                    // Update the model in LanguageModelStore
                    if let localModelSD = LanguageModelStore.shared.models.first(where: { $0.name == firstModel.name }) {
                        LanguageModelStore.shared.setModel(model: localModelSD)
                    } else {
                        print("Selected local model not found in LanguageModelStore")
                    }
                } else {
                    print("No local models available for auto-selection")
                }
            }
        }
    }
    
    func selectPreferredLocalModel() async {
        // Get available local models
        if let localModels = try? await LocalModelService.shared.getModels(),
           !localModels.isEmpty {
            // Select the first available local model
            DispatchQueue.main.async {
                let localModelName = localModels.first!.name
                // Find the corresponding LanguageModelSD
                if let localModel = LanguageModelStore.shared.models.first(where: { $0.name == localModelName }) {
                    LanguageModelStore.shared.setModel(model: localModel)
                }
            }
        }
    }
}

#Preview {
    SettingsView(
        ollamaUri: .constant(""),
        systemPrompt: .constant("You are an intelligent assistant solving complex problems. You are an intelligent assistant solving complex problems. You are an intelligent assistant solving complex problems."),
        vibrations: .constant(true),
        colorScheme: .constant(.light),
        defaultOllamModel: .constant("llama2"),
        ollamaBearerToken: .constant("x"),
        appUserInitials: .constant("AM"),
        pingInterval: .constant("5"),
        voiceIdentifier: .constant("sample"),
        save: {},
        checkServer: {},
        deleteAll: {},
        ollamaLangugeModels: LanguageModelSD.sample,
        voices: []
    )
}

