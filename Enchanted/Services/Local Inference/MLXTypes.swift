//
//  MLXTypes.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/23/25.
//

import Foundation
import MLX

/// Role type for chat messages
public enum Role: String, Codable {
    case system
    case user
    case bot
}

/// Chat message structure for MLX models
public struct MLXMessage: Identifiable, Equatable {
    public var id: UUID
    public var role: Role
    public var content: String
    
    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

/// Model architectures supported by MLX
public enum ModelArchitecture: String, Codable {
    case llama
    case phi
    case gemma
    case mistral
    case unknown
}

/// Types of tokenizers supported by MLX
public enum TokenizerType: String, Codable {
    case sentencePiece
    case bpe
    case wordPiece
}

/// Prompt format types for different models
public enum ModelPromptFormat: String, Codable {
    case llama3
    case llama2
    case gemma
    case phi
    case mistral
}

/// Error types for MLX model operations
public enum MLXModelError: Error, LocalizedError {
    case modelNotFound
    case modelNotInitialized
    case failedToLoadModel
    case tokenizerNotFound
    case incompatibleModel
    case inferenceError(String)
    
    public var errorDescription: String? {
        switch self {
            case .modelNotFound:
                return "MLX model file not found on device"
            case .modelNotInitialized:
                return "Failed to initialize MLX model"
            case .failedToLoadModel:
                return "Failed to load MLX model"
            case .tokenizerNotFound:
                return "Tokenizer file not found for MLX model"
            case .incompatibleModel:
                return "MLX model is not compatible with this device"
            case .inferenceError(let details):
                return "MLX inference error: \(details)"
        }
    }
}

/// A protocol for tokenizers to standardize the interface
public protocol MLXTokenizer {
    /// Encode text to token IDs
    func encode(text: String, addBos: Bool) -> [Int]
    
    /// Decode token IDs to text
    func decode(tokens: [Int]) -> String
}

/// Inference metrics for tracking performance
public struct InferenceMetrics {
    public var inputTokenCount: Int32 = 0
    public var outputTokenCount: Int32 = 0
    public var startTime: Date?
    public var endTime: Date?
    
    public mutating func start() {
        startTime = Date()
        outputTokenCount = 0
    }
    
    public mutating func stop() {
        endTime = Date()
    }
    
    public mutating func recordToken() {
        outputTokenCount += 1
    }
    
    public var elapsedTime: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    public var tokensPerSecond: Double? {
        guard let elapsed = elapsedTime, elapsed > 0 else { return nil }
        return Double(outputTokenCount) / elapsed
    }
}

/// Model download information
public struct MLXModelDownloadInfo: Identifiable {
    public var id: String { name }
    public var name: String
    public var displayName: String
    public var url: URL
    public var fileExtension: String
    public var tokenizerURL: URL?
    public var size: String
    public var promptFormat: ModelPromptFormat
    
    public init(
        name: String,
        displayName: String,
        url: URL,
        fileExtension: String,
        tokenizerURL: URL? = nil,
        size: String,
        promptFormat: ModelPromptFormat
    ) {
        self.name = name
        self.displayName = displayName
        self.url = url
        self.fileExtension = fileExtension
        self.tokenizerURL = tokenizerURL
        self.size = size
        self.promptFormat = promptFormat
    }
}
