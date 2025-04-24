//
//  ModelStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData
import MLX
import Combine

@Observable
final class LanguageModelStore {
    static let shared = LanguageModelStore(swiftDataService: SwiftDataService.shared)
    
    var swiftDataService: SwiftDataService
    @MainActor var models: [LanguageModelSD] = []
    @MainActor var supportsImages = false
    @MainActor var selectedModel: LanguageModelSD?
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    // Initialize with MLX and Ollama models
    @MainActor
    func initialize() async {
        print("Initializing LanguageModelStore")
        
        // Check if we need to load local models
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        print("Local inference enabled: \(useLocalInference)")
        
        // Initialize models with MLX support
        await MLXIntegration.shared.initializeMixedModels(languageModelStore: self)
        
        // Make sure we have a selected model
        selectAppropriateModel()
        
        print("Model initialization complete. Models count: \(models.count), Selected model: \(selectedModel?.name ?? "none")")
    }
    
    // Refresh models with MLX support
    @MainActor
    func refreshModelsWithMLX() async {
        print("Refreshing models with MLX")
        
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        print("Local inference enabled: \(useLocalInference)")
        
        // Get MLX models
        var mlxModels: [LanguageModelSD] = []
        
        do {
            let localMLXModels = try await MLXLocalModelService.shared.getModels()
            mlxModels = localMLXModels.map {
                LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .local)
            }
            print("Found \(mlxModels.count) MLX models")
        } catch {
            print("Error fetching MLX models: \(error)")
        }
        
        // Get Ollama models if not using local inference or if we want both
        var ollamaModels: [LanguageModelSD] = []
        let ollamaRechable = await OllamaService.shared.reachable()
        if (!useLocalInference || UserDefaults.standard.bool(forKey: "showBothBackends")) && ollamaRechable {
            do {
                let remoteModels = try await OllamaService.shared.getModels()
                ollamaModels = remoteModels.map {
                    LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .ollama)
                }
                print("Found \(ollamaModels.count) Ollama models")
            } catch {
                print("Error fetching Ollama models: \(error)")
            }
        }
        
        // Combine models
        let combinedModels = mlxModels + ollamaModels
        
        // Save models to SwiftData
        if !combinedModels.isEmpty {
            do {
                // First clear existing models
                try await deleteAllModels()
                
                // Then save new models
                try await swiftDataService.saveModels(models: combinedModels)
                
                // Fetch and update models
                models = try await swiftDataService.fetchModels()
                
                // Select appropriate model
                selectAppropriateModel()
            } catch {
                print("Error saving models: \(error)")
            }
        }
    }
    
    // Select the appropriate model based on settings
    @MainActor
    private func selectAppropriateModel() {
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        let selectedLocalModelName = UserDefaults.standard.string(forKey: "selectedLocalModel") ?? ""
        let defaultOllamaModel = UserDefaults.standard.string(forKey: "defaultOllamaModel") ?? ""
        
        if useLocalInference {
            // Try to find the selected local model
            if !selectedLocalModelName.isEmpty,
               let localModel = models.first(where: { $0.name == selectedLocalModelName && $0.modelProvider == .local }) {
                selectedModel = localModel
                supportsImages = localModel.supportsImages
                return
            }
            
            // Try to find any MLX model
            if let mlxModel = models.first(where: { $0.name.lowercased().contains("mlx") && $0.modelProvider == .local }) {
                selectedModel = mlxModel
                supportsImages = mlxModel.supportsImages
                // Update selected model name
                UserDefaults.standard.set(mlxModel.name, forKey: "selectedLocalModel")
                return
            }
            
            // Try to find any local model
            if let localModel = models.first(where: { $0.modelProvider == .local }) {
                selectedModel = localModel
                supportsImages = localModel.supportsImages
                // Update selected model name
                UserDefaults.standard.set(localModel.name, forKey: "selectedLocalModel")
                return
            }
        }
        
        // Fall back to Ollama model
        if !defaultOllamaModel.isEmpty,
           let ollamaModel = models.first(where: { $0.name == defaultOllamaModel && $0.modelProvider == .ollama }) {
            selectedModel = ollamaModel
            supportsImages = ollamaModel.supportsImages
        } else if let firstOllamaModel = models.first(where: { $0.modelProvider == .ollama }) {
            selectedModel = firstOllamaModel
            supportsImages = firstOllamaModel.supportsImages
        }
    }
    
    // Load models - now just calls refreshModelsWithMLX
    func loadModels() async throws {
        await refreshModelsWithMLX()
    }
    
    // Set selected model
    @MainActor
    func setModel(model: LanguageModelSD?) {
        print("Setting model: \(model?.name ?? "nil")")
        if let model = model {
            // check if model still exists
            if models.contains(model) {
                selectedModel = model
                supportsImages = model.supportsImages
                
                // If this is a local model, update the selected local model preference
                if model.modelProvider == .local {
                    UserDefaults.standard.set(model.name, forKey: "selectedLocalModel")
                    
                    // Also enable local inference
                    UserDefaults.standard.set(true, forKey: "useLocalInference")
                } else if model.modelProvider == .ollama {
                    // If it's an Ollama model, update the default Ollama model
                    UserDefaults.standard.set(model.name, forKey: "defaultOllamaModel")
                }
            }
        } else {
            selectedModel = nil
            supportsImages = false
        }
    }
    
    // Set model by name
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
    
    // Delete all models
    func deleteAllModels() async throws {
        DispatchQueue.main.async {
            self.models = []
        }
        try await swiftDataService.deleteModels()
    }
    
    // Refresh models on notification
    @MainActor
    func setupNotificationObservers() {
        // Listen for model selection changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LocalModelSelected"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let modelName = notification.object as? String {
                self?.setModel(modelName: modelName)
            }
        }
        
        // Listen for model downloads and deletions
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModelDownloadCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshModelsWithMLX()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModelDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshModelsWithMLX()
            }
        }
    }
}
