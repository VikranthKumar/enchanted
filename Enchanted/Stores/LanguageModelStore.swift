//
//  ModelStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

@Observable
final class LanguageModelStore {
    static let shared = LanguageModelStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    @MainActor var models: [LanguageModelSD] = [] // Initialize with empty array instead of nil
    @MainActor var supportsImages = false
    @MainActor var selectedModel: LanguageModelSD?
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    // Add initializer for models on startup
    @MainActor
    func initialize() async {
        print("Initializing LanguageModelStore")
        
        // Check if we need to load local models
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        print("Local inference enabled: \(useLocalInference)")
        
        if useLocalInference {
            // Try to load local models first
            do {
                try await loadLocalModelsOnly()
                print("Successfully loaded local models")
            } catch {
                print("Failed to load local models: \(error)")
            }
        } else {
            // Load regular Ollama models
            do {
                try await loadOllamaModels()
                print("Successfully loaded Ollama models")
            } catch {
                print("Failed to load Ollama models: \(error)")
            }
        }
        
        // Make sure we have a selected model
        selectPreferredModel()
        
        print("Model initialization complete. Models count: \(models.count), Selected model: \(selectedModel?.name ?? "none")")
    }
    
    // Separate method to load only local models
    @MainActor
    func loadLocalModelsOnly() async throws {
        print("Loading only local models")
        
        // Get local models
        let localModels = try await LocalModelService.shared.getModels()
        print("Found \(localModels.count) local models")
        
        // Save models to SwiftData
        try await swiftDataService.saveModels(models: localModels.map {
            LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .local)
        })
        
        // Fetch all models from SwiftData
        let storedModels = (try? await swiftDataService.fetchModels()) ?? []
        let localModelNames = localModels.map { $0.name }
        
        // Filter to only include local models
        models = storedModels.filter { localModelNames.contains($0.name) && $0.modelProvider == .local }
        
        print("Loaded \(models.count) local models")
        
        // Select a local model if available
        if !models.isEmpty {
            let selectedLocalModelName = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
            
            if !selectedLocalModelName.isEmpty,
               let selectedLocalModel = models.first(where: { $0.name == selectedLocalModelName }) {
                self.selectedModel = selectedLocalModel
                print("Selected local model: \(selectedLocalModel.name)")
            } else {
                self.selectedModel = models.first
                if let model = selectedModel {
                    UserDefaults.standard.set(model.name, forKey: "selectedLocalModel")
                    print("Auto-selected local model: \(model.name)")
                }
            }
        }
    }
    
    // Separate method to load only Ollama models
    @MainActor
    func loadOllamaModels() async throws {
        print("Loading Ollama models")
        
        // Get Ollama models
        let remoteModels = try await OllamaService.shared.getModels()
        print("Found \(remoteModels.count) Ollama models")
        
        // Save models to SwiftData
        try await swiftDataService.saveModels(models: remoteModels.map {
            LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .ollama)
        })
        
        // Fetch all models from SwiftData
        let storedModels = (try? await swiftDataService.fetchModels()) ?? []
        let remoteModelNames = remoteModels.map { $0.name }
        
        // Filter to only include Ollama models
        models = storedModels.filter { remoteModelNames.contains($0.name) && $0.modelProvider == .ollama }
        
        print("Loaded \(models.count) Ollama models")
        
        // Select an Ollama model if available
        if !models.isEmpty {
            let defaultOllamaModel = UserDefaults.standard.string(forKey: "defaultOllamaModel") ?? ""
            
            if !defaultOllamaModel.isEmpty,
               let selectedOllamaModel = models.first(where: { $0.name == defaultOllamaModel }) {
                self.selectedModel = selectedOllamaModel
                print("Selected default Ollama model: \(selectedOllamaModel.name)")
            } else {
                self.selectedModel = models.first
                if let model = selectedModel {
                    print("Auto-selected Ollama model: \(model.name)")
                }
            }
        }
    }
    
    // Modified loadModels to leverage the new methods
    func loadModels() async throws {
        print("Loading all models")
        
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        
        if useLocalInference {
            // Load local models
            try await loadLocalModelsOnly()
        } else {
            // Load Ollama models
            try await loadOllamaModels()
        }
        
    }
    
    @MainActor
    func setModel(model: LanguageModelSD?) {
        print(model)
        if let model = model {
            // check if model still exists
            if models.contains(model) {
                selectedModel = model
            }
        } else {
            selectedModel = nil
        }
    }
    
    @MainActor
    func setModel(modelName: String) {
        for model in models {
            if model.name == modelName {
                setModel(model: model)
                return
            }
        }
        if let lastModel = models.last {
            setModel(model: lastModel)
        }
    }
    
    @MainActor
    func selectPreferredModel() {
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        let selectedLocalModelName = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
        
        if useLocalInference {
            // Try to find the selected local model first if one is specified
            if !selectedLocalModelName.isEmpty {
                if let localModel = models.first(where: { $0.name == selectedLocalModelName && $0.modelProvider == .local }) {
                    selectedModel = localModel
                    return
                }
            }
            
            // Try to find any local model if selected one not found
            if let localModel = models.first(where: { $0.modelProvider == .local }) {
                selectedModel = localModel
                // Update selected model name
                UserDefaults.standard.set(localModel.name, forKey: "selectedLocalModel")
                return
            }
        }
        
        // Fall back to Ollama model if needed or if local inference is disabled
        if let ollamaModel = models.first(where: { $0.modelProvider == .ollama }) {
            selectedModel = ollamaModel
        }
    }
    
    @MainActor
    func setModelByName(modelName: String) {
        for model in models {
            if model.name == modelName {
                selectedModel = model
                
                // If this is a local model, update the selected local model preference
                if model.modelProvider == .local {
                    UserDefaults.standard.set(model.name, forKey: "selectedLocalModel")
                }
                
                return
            }
        }
    }
    
    func deleteAllModels() async throws {
        DispatchQueue.main.async {
            self.models = []
        }
        try await swiftDataService.deleteModels()
    }
}
