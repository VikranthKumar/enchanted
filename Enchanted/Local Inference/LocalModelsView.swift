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
    
    func loadDownloadedModels() {
        Task {
            do {
                let models = try await LocalModelService.shared.getModels()
                DispatchQueue.main.async {
                    self.downloadedModels = models
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
            case .phi:
                return "Phi"
            case .llama2:
                return "Llama 2"
            case .llama3:
                return "Llama 3"
            case .gemma:
                return "Gemma"
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Local Models")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
            
            List {
                
                Section(header: Text("Available Models")) {
                    ForEach(LocalModelService.availableModels) { model in
                        VStack(alignment: .leading) {
                            HStack {
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
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        
                                        Button(action: {
                                            do {
                                                try localModelService.deleteModel(name: model.name)
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
                    }
                }
                Section(header: Text("Downloaded Models")) {
                    if downloadedModels.isEmpty {
                        Text("No models downloaded yet")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(downloadedModels, id: \.self) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.headline)
                                    
                                    Text("Ready for local inference")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("Local")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(Capsule())
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
#if os(iOS) || os(VisionOS)
            .listStyle(GroupedListStyle())
#endif
            .refreshable {
                loadDownloadedModels()
            }
        }
        .onAppear {
            loadDownloadedModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
            loadDownloadedModels()
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
