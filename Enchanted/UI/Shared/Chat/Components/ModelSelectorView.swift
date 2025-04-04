//
//  ModelSelector.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI

struct ModelSelectorView: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: @MainActor (_ model: LanguageModelSD?) -> ()
    var showChevron = true
    
    // Add states for local model support
    @State private var localModels: [LanguageModel] = []
    @AppStorage("selectedLocalModel") private var selectedLocalModel: String = ""
    @AppStorage("useLocalInference") private var useLocalInference: Bool = false
    @State private var showLocalModelsSheet = false
    
    // Load local models
    func loadLocalModels() {
        Task {
            if useLocalInference, let models = try? await LocalModelService.shared.getModels() {
                DispatchQueue.main.async {
                    self.localModels = models
                    
                    // If we have no selected local model but have local models, select the first one
                    if selectedLocalModel.isEmpty && !models.isEmpty {
                        selectedLocalModel = models[0].name
                        // Find the corresponding LanguageModelSD
                        updateLocalModelSelection(models[0].name)
                    }
                }
            }
        }
    }
    
    // Update selected model when a local model is selected
    func updateLocalModelSelection(_ modelName: String) {
        if let model = modelsList.first(where: { $0.name == modelName && $0.modelProvider == .local }) {
            onSelectModel(model)
        } else {
            // If model isn't in modelsList yet, we need to refresh the list
            print("Selected local model not in models list, refreshing...")
            Task {
                try? await LanguageModelStore.shared.loadLocalModelsOnly()
                
                // Try again after refresh
                DispatchQueue.main.async {
                    if let model = LanguageModelStore.shared.models.first(where: { $0.name == modelName }) {
                        onSelectModel(model)
                    }
                }
            }
        }
    }
    
    var body: some View {
        Group {
            if useLocalInference {
                // Local inference menu
                Menu {
                    if localModels.isEmpty {
                        Text("No local models available")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        Button(action: {
                            showLocalModelsSheet = true
                        }) {
                            Label("Download Models...", systemImage: "square.and.arrow.down")
                        }
                    } else {
                        ForEach(localModels, id: \.self) { model in
                            Button(action: {
                                selectedLocalModel = model.name
                                updateLocalModelSelection(model.name)
                            }) {
                                HStack {
                                    Text(model.name)
                                    
                                    Spacer()
                                    
                                    if selectedLocalModel == model.name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            showLocalModelsSheet = true
                        }) {
                            Label("Manage Models...", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    HStack(alignment: .center) {
                        if let selectedModel = selectedModel, selectedModel.modelProvider == .local, !selectedLocalModel.isEmpty {
                            HStack(alignment: .bottom, spacing: 5) {
                                
#if os(macOS) || os(visionOS)
                                Text(selectedModel.name)
                                    .font(.body)
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "cpu")
                                        .font(.caption)
                                    
                                    Text("Local")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
#elseif os(iOS)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(selectedModel.prettyName)
                                            .font(.body)
                                            .foregroundColor(Color.labelCustom)
                                        
                                        HStack(spacing: 2) {
                                            Image(systemName: "cpu")
                                                .font(.caption)
                                            
                                            Text("Local")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green)
                                        .clipShape(Capsule())
                                    }
                                    
                                }
#endif
                            }
                        } else {
                            Text(selectedLocalModel.isEmpty ? "Select Local Model" : selectedLocalModel)
                                .foregroundColor(Color.labelCustom)
                        }
                        
                        Image(systemName: "chevron.down")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10)
                            .foregroundColor(Color(.label))
                            .showIf(showChevron)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showLocalModelsSheet) {
                    LocalModelsView()
                        .modifier(SheetSizeModifier())
                }
                .onAppear {
                    loadLocalModels()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
                    loadLocalModels()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDeleted"))) { notification in
                    loadLocalModels()
                }
            } else {
                Menu {
                    ForEach(modelsList.filter { $0.modelProvider == .ollama }, id: \.self) { model in
                        Button(action: {
                            withAnimation(.easeOut) {
                                onSelectModel(model)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.body)
                                        .tag(model.name)
                                }
                                
                                Spacer()
                                
                                if model.name == selectedModel?.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(alignment: .center) {
                        if let selectedModel = selectedModel, selectedModel.modelProvider == .ollama {
                            HStack(alignment: .bottom, spacing: 5) {
                                
#if os(macOS) || os(visionOS)
                                Text(selectedModel.name)
                                    .font(.body)
#elseif os(iOS)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(selectedModel.prettyName)
                                            .font(.body)
                                            .foregroundColor(Color.labelCustom)
                                    }
                                    
                                    Text(selectedModel.prettyVersion)
                                        .font(.subheadline)
                                        .foregroundColor(Color.gray3Custom)
                                }
#endif
                            }
                        } else {
                            Text("Select Model")
                        }
                        
                        Image(systemName: "chevron.down")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10)
                            .foregroundColor(Color(.label))
                            .showIf(showChevron)
                    }
                }
            }
        }
    }
}
