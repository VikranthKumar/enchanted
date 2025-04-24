//
//  MLXModelsView.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import SwiftUI

/// View for displaying and managing MLX models
struct MLXModelsView: View {
    @State private var downloadProgress: [String: Double] = [:]
    @State private var availableModels: [MLXModelDownloadInfo] = []
    @State private var installedModels: [LanguageModel] = []
    @State private var isLoading = true
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    // Environment properties
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Installed MLX Models")) {
                    if installedModels.isEmpty && !isLoading {
                        Text("No MLX models installed")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(installedModels, id: \.name) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.headline)
                                    Text("Local ML Model")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Set as selected model button
                                Button(action: {
                                    setSelectedModel(model.name)
                                }) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(isModelSelected(model.name) ? .green : .gray)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .padding(.horizontal, 4)
                                
                                // Delete button
                                Button(action: {
                                    deleteModel(model.name)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section(header: Text("Available MLX Models")) {
                    Text("MLX models run directly on your device using Apple's ML framework. They don't require an internet connection after downloading.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    
                    if availableModels.isEmpty && !isLoading {
                        Text("No MLX models available for download")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(availableModels) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.headline)
                                    Text("\(model.size) • \(model.promptFormat.rawValue.capitalized) Format")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let progress = downloadProgress[model.name] {
                                    if progress < 1.0 {
                                        VStack(spacing: 2) {
                                            ProgressView(value: progress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                                .frame(width: 100)
                                            Text("\(Int(progress * 100))%")
                                                .font(.caption2)
                                        }
                                        
                                        Button(action: {
                                            cancelDownload(model.name)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .padding(.leading, 4)
                                    } else {
                                        Text("Installing...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else if isModelInstalled(model.name) {
                                    Text("Installed")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Button(action: {
                                        downloadModel(model)
                                    }) {
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section(header: Text("About MLX")) {
                    HStack {
                        Text("MLX is Apple's machine learning framework designed for Apple Silicon. Models run locally on your device with no data sent to external servers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .refreshable {
                await refreshModels()
            }
            .onAppear {
                Task {
                    await refreshModels()
                }
                
                // Setup notification observers for download progress updates
                downloadProgress = MLXLocalModelService.shared.downloadProgress
                
                // Listen for download progress updates
                NotificationCenter.default.addObserver(forName: NSNotification.Name("ModelDownloadCompleted"), object: nil, queue: .main) { _ in
                    Task {
                        await refreshModels()
                    }
                }
                
                NotificationCenter.default.addObserver(forName: NSNotification.Name("ModelDeleted"), object: nil, queue: .main) { _ in
                    Task {
                        await refreshModels()
                    }
                }
            }
            .navigationTitle("MLX Models")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // Refresh the list of models
    private func refreshModels() async {
        isLoading = true
        
        // Get available models for download
        availableModels = MLXLocalModelService.availableModels
        
        // Get installed models
        do {
            installedModels = try await MLXLocalModelService.shared.getModels()
        } catch {
            print("Error fetching installed models: \(error)")
            showAlert(title: "Error", message: "Failed to fetch installed models: \(error.localizedDescription)")
        }
        
        // Update download progress
        downloadProgress = MLXLocalModelService.shared.downloadProgress
        
        isLoading = false
    }
    
    // Download a model
    private func downloadModel(_ model: MLXModelDownloadInfo) {
        MLXLocalModelService.shared.downloadModel(model: model)
        // Progress will be updated through binding
    }
    
    // Cancel a download
    private func cancelDownload(_ modelName: String) {
        MLXLocalModelService.shared.cancelDownload(name: modelName)
    }
    
    // Delete a model
    private func deleteModel(_ modelName: String) {
        do {
            try MLXLocalModelService.shared.deleteModel(name: modelName)
        } catch {
            print("Error deleting model: \(error)")
            showAlert(title: "Error", message: "Failed to delete model: \(error.localizedDescription)")
        }
    }
    
    // Check if a model is installed
    private func isModelInstalled(_ modelName: String) -> Bool {
        return installedModels.contains(where: { $0.name == modelName })
    }
    
    // Check if a model is selected
    private func isModelSelected(_ modelName: String) -> Bool {
        return UserDefaults.standard.string(forKey: "selectedLocalModel") == modelName
    }
    
    // Set selected model
    private func setSelectedModel(_ modelName: String) {
        UserDefaults.standard.set(modelName, forKey: "selectedLocalModel")
        UserDefaults.standard.set(true, forKey: "useLocalInference")
        
        // Set notification so the model store refreshes
        NotificationCenter.default.post(name: NSNotification.Name("LocalModelSelected"), object: modelName)
        
        showAlert(title: "Model Selected", message: "Local inference enabled with model '\(modelName)'")
    }
    
    // Show alert
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

// Extension for sheet size
struct MLXSheetSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content
            .frame(width: 600, height: 500)
#else
        content
#endif
    }
}

// Add the view preview
#Preview {
    MLXModelsView()
        .modifier(MLXSheetSizeModifier())
}
