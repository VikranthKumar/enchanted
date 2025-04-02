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
    @MainActor var models: [LanguageModelSD] = []
    @MainActor var supportsImages = false
    @MainActor var selectedModel: LanguageModelSD?
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    @MainActor
    func setModel(model: LanguageModelSD?) {
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
    
    func loadModels() async throws {
        // Get Ollama models
        let remoteModels = try await OllamaService.shared.getModels()
        try await swiftDataService.saveModels(models: remoteModels.map{LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .ollama)})
        
        // Get local models if enabled
        let useLocalInference = UserDefaults.standard.bool(forKey: "useLocalInference")
        var localModels: [LanguageModel] = []
        
        if useLocalInference {
            localModels = try await LocalModelService.shared.getModels()
            try await swiftDataService.saveModels(models: localModels.map{LanguageModelSD(name: $0.name, imageSupport: $0.imageSupport, modelProvider: .local)})
        }
        
        let storedModels = (try? await swiftDataService.fetchModels()) ?? []
        
        DispatchQueue.main.async {
            let remoteModelNames = remoteModels.map { $0.name }
            let localModelNames = localModels.map { $0.name }
            
            if useLocalInference {
                self.models = storedModels.filter{remoteModelNames.contains($0.name) || localModelNames.contains($0.name)}
            } else {
                self.models = storedModels.filter{remoteModelNames.contains($0.name)}
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
