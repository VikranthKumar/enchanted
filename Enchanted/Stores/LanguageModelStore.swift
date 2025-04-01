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
