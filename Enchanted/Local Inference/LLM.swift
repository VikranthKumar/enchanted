//
//  LLM.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import Foundation
import Combine
import OllamaKit

/// Protocol that defines a common interface for language models
protocol LLM {
    /// Checks if the model server is reachable
    func reachable() async -> Bool
    
    /// Generate a response from the model
    func chat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error>
}

/// Factory class to get the appropriate LLM implementation
class LLMFactory {
    static func getLLM(for model: LanguageModelSD) -> LLM {
        switch model.modelProvider {
            case .local:
                return LocalModelService.shared
            default:
                return OllamaLLM.shared
        }
    }
}

/// Wrapper around OllamaService to conform to LLM protocol
class OllamaLLM: LLM {
    static let shared = OllamaLLM()
    
    private init() {}
    
    func reachable() async -> Bool {
        return await OllamaService.shared.reachable()
    }
    
    func chat(data: OKChatRequestData) -> AnyPublisher<OKChatResponse, Error> {
        return OllamaService.shared.ollamaKit.chat(data: data)
    }
}
