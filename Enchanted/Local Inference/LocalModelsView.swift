//
//  LocalModelsView.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import SwiftUI

struct LocalModelsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var localModelService = LocalModelService.shared
    @State private var downloadedModels: [LanguageModel] = []
    @AppStorage("selectedLocalModel") private var selectedLocalModel: String = ""
    
    func loadDownloadedModels() {
        Task {
            do {
                let models = try await LocalModelService.shared.getModels()
                DispatchQueue.main.async {
                    self.downloadedModels = models
                    
                    // If no model is selected yet but we have models, select the first one
                    if selectedLocalModel.isEmpty && !models.isEmpty {
                        selectedLocalModel = models[0].name
                        
                        // Apply the selection
                        applyModelSelection(selectedLocalModel)
                    }
                }
            } catch {
                print("Failed to load downloaded models: \(error)")
            }
        }
    }
    
    func isDownloaded(model: ModelDownloadInfo) -> Bool {
        return localModelService.modelExists(name: model.name)
    }
    
    func getPromptFormatName(_ format: ModelPromptFormat) -> String {
        switch format {
            case .llama2:
                return "Llama 2"
            case .llama3:
                return "Llama 3"
            case .gemma:
                return "Gemma"
            case .phi:
                return "Phi"
        }
    }
    
    func applyModelSelection(_ modelName: String) {
        // Update the selection in UserDefaults
        UserDefaults.standard.set(modelName, forKey: "selectedLocalModel")
        
        // Try to find the model in LanguageModelStore and select it
        Task {
            // Make sure models are loaded
            try? await LanguageModelStore.shared.loadModels()
            
            DispatchQueue.main.async {
                if let localModel = LanguageModelStore.shared.models.first(where: { $0.name == modelName }) {
                    LanguageModelStore.shared.setModel(model: localModel)
                    
                    // Post notification that model has been selected
                    NotificationCenter.default.post(name: NSNotification.Name("LocalModelSelected"), object: nil)
                }
            }
        }
    }
    
    var list: some View {
        List {
            Section(header: Text("Available Models")) {
                ForEach(LocalModelService.availableModels) { model in
                    VStack(alignment: .leading) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.headline)
                                
                                HStack {
                                    Text("Size: \(model.size)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("•")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Format: \(getPromptFormatName(model.promptFormat))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if localModelService.downloadProgress[model.name] != nil {
                                VStack {
                                    ProgressView(value: localModelService.downloadProgress[model.name] ?? 0)
                                        .progressViewStyle(LinearProgressViewStyle())
                                        .frame(width: 100)
                                    
                                    Text("\(Int((localModelService.downloadProgress[model.name] ?? 0) * 100))%")
                                        .font(.caption)
                                }
                                .frame(width: 100)
                                
                                Button(action: {
                                    localModelService.cancelDownload(name: model.name)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else if isDownloaded(model: model) {
                                HStack {
                                    if selectedLocalModel == model.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                    
                                    Button(action: {
                                        do {
                                            try localModelService.deleteModel(name: model.name)
                                            
                                            // If we're deleting the selected model, clear selection
                                            if selectedLocalModel == model.name {
                                                selectedLocalModel = ""
                                            }
                                            
                                            loadDownloadedModels()
                                        } catch {
                                            print("Failed to delete model: \(error)")
                                        }
                                    }) {
                                        Text("Delete")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(BorderedButtonStyle())
                                }
                            } else {
                                Button(action: {
                                    localModelService.downloadModel(model: model)
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle")
                                        Text("Download")
                                    }
                                }
                                .buttonStyle(BorderedButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .onTapGesture {
                        if isDownloaded(model: model) {
                            selectedLocalModel = model.name
                            applyModelSelection(model.name)
                        }
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About Local Models")
                        .font(.headline)
                    
                    Text("Models are downloaded directly to your device and run locally without requiring an internet connection or Ollama server.")
                        .font(.caption)
                    
                    Text("Local inference is powered by SwiftLlama, a Swift wrapper for llama.cpp.")
                        .font(.caption)
                }
                .padding(.vertical, 8)
            }
        }
//        .listStyle(GroupedListStyle())
        .refreshable {
            loadDownloadedModels()
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Local Models")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding([.top, .horizontal])
#if os(macOS)
            .padding(.top, 20)
#endif
            
            list
        }
        .modifier(SheetSizeModifier())
        .onAppear {
            loadDownloadedModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
            loadDownloadedModels()
            
            // If no model is currently selected, select the newly downloaded one
            if selectedLocalModel.isEmpty {
                Task {
                    let models = try? await LocalModelService.shared.getModels()
                    
                    DispatchQueue.main.async {
                        if let firstModel = models?.first {
                            selectedLocalModel = firstModel.name
                            applyModelSelection(firstModel.name)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
struct LocalModelsView_Previews: PreviewProvider {
    static var previews: some View {
        LocalModelsView()
    }
}
#endif

struct SheetSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content
            .frame(minWidth: 700, minHeight: 400)
            .padding(.bottom, 20) // Add some bottom padding for macOS sheets
#else
        content
#endif
    }
}
