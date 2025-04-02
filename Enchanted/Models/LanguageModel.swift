//
//  LanguageModel.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 12/05/2024.
//

import Foundation

struct LanguageModel: Hashable {
    var name: String
    var provider: ModelProvider
    var imageSupport: Bool
}

enum ModelProvider: String, Codable {
    case ollama
    case local
}
