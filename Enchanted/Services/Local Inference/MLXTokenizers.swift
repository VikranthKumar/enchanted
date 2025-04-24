//
//  MLXTokenizers.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/23/25.
//

import Foundation
import MLX

/// Base implementation for SentencePiece tokenizer
public class SentencePieceTokenizer: MLXTokenizer {
    private let modelPath: String
    private var vocabulary: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private let specialTokens: [String: Int]
    
    public init(modelPath: String) {
        self.modelPath = modelPath
        
        // These would normally be loaded from the model file
        // This is a simplified implementation
        self.specialTokens = [
            "<s>": 1,
            "</s>": 2,
            "<unk>": 0
        ]
        
        loadVocabulary()
    }
    
    private func loadVocabulary() {
        // In a real implementation, this would parse the SentencePiece model file
        // For now, we'll just use a minimal vocabulary for testing
        vocabulary["hello"] = 100
        vocabulary["world"] = 101
        vocabulary["test"] = 102
        
        // Also create the reverse mapping
        for (token, id) in vocabulary {
            idToToken[id] = token
        }
        
        // Add special tokens to both mappings
        for (token, id) in specialTokens {
            vocabulary[token] = id
            idToToken[id] = token
        }
    }
    
    public func encode(text: String, addBos: Bool) -> [Int] {
        // In a real implementation, this would use the SentencePiece algorithm
        // For testing, we'll just split by space and look up in the vocabulary
        
        var tokens: [Int] = []
        
        // Add BOS token if requested
        if addBos {
            tokens.append(specialTokens["<s>"]!)
        }
        
        // Simple encoding: split by spaces and convert to tokens
        let words = text.split(separator: " ")
        for word in words {
            let wordStr = String(word)
            if let id = vocabulary[wordStr] {
                tokens.append(id)
            } else {
                // Unknown token
                tokens.append(specialTokens["<unk>"]!)
            }
        }
        
        return tokens
    }
    
    public func decode(tokens: [Int]) -> String {
        // Convert token IDs back to strings and join
        let words = tokens.map { id -> String in
            idToToken[id] ?? "<unk>"
        }
        
        return words.joined(separator: " ")
    }
}

/// Base implementation for BPE tokenizer
public class BPETokenizer: MLXTokenizer {
    private let vocabPath: String
    private var vocabulary: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private let specialTokens: [String: Int]
    
    public init(vocabPath: String) {
        self.vocabPath = vocabPath
        
        // These would normally be loaded from the tokenizer JSON file
        self.specialTokens = [
            "<s>": 1,
            "</s>": 2,
            "<unk>": 0
        ]
        
        loadVocabulary()
    }
    
    private func loadVocabulary() {
        // In a real implementation, this would parse the BPE vocabulary file
        // For now, we'll just use a minimal vocabulary for testing
        vocabulary["hello"] = 100
        vocabulary["world"] = 101
        vocabulary["test"] = 102
        
        // Also create the reverse mapping
        for (token, id) in vocabulary {
            idToToken[id] = token
        }
        
        // Add special tokens to both mappings
        for (token, id) in specialTokens {
            vocabulary[token] = id
            idToToken[id] = token
        }
    }
    
    public func encode(text: String, addBos: Bool) -> [Int] {
        // In a real implementation, this would use the BPE algorithm
        // For testing, we'll just split by space and look up in the vocabulary
        
        var tokens: [Int] = []
        
        // Add BOS token if requested
        if addBos {
            tokens.append(specialTokens["<s>"]!)
        }
        
        // Simple encoding: split by spaces and convert to tokens
        let words = text.split(separator: " ")
        for word in words {
            let wordStr = String(word)
            if let id = vocabulary[wordStr] {
                tokens.append(id)
            } else {
                // Unknown token
                tokens.append(specialTokens["<unk>"]!)
            }
        }
        
        return tokens
    }
    
    public func decode(tokens: [Int]) -> String {
        // Convert token IDs back to strings and join
        let words = tokens.map { id -> String in
            idToToken[id] ?? "<unk>"
        }
        
        return words.joined(separator: " ")
    }
}

/// WordPiece tokenizer implementation (used by BERT and other models)
public class WordPieceTokenizer: MLXTokenizer {
    private let vocabPath: String
    private var vocabulary: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private let specialTokens: [String: Int]
    
    public init(vocabPath: String) {
        self.vocabPath = vocabPath
        
        // These would normally be loaded from the vocabulary file
        self.specialTokens = [
            "[CLS]": 101,
            "[SEP]": 102,
            "[UNK]": 100
        ]
        
        loadVocabulary()
    }
    
    private func loadVocabulary() {
        // In a real implementation, this would parse the WordPiece vocabulary file
        // For now, we'll just use a minimal vocabulary for testing
        vocabulary["hello"] = 1000
        vocabulary["world"] = 1001
        vocabulary["test"] = 1002
        
        // Also create the reverse mapping
        for (token, id) in vocabulary {
            idToToken[id] = token
        }
        
        // Add special tokens to both mappings
        for (token, id) in specialTokens {
            vocabulary[token] = id
            idToToken[id] = token
        }
    }
    
    public func encode(text: String, addBos: Bool) -> [Int] {
        // In a real implementation, this would use the WordPiece algorithm
        // For testing, we'll just split by space and look up in the vocabulary
        
        var tokens: [Int] = []
        
        // Add BOS token if requested
        if addBos {
            tokens.append(specialTokens["[CLS]"]!)
        }
        
        // Simple encoding: split by spaces and convert to tokens
        let words = text.split(separator: " ")
        for word in words {
            let wordStr = String(word)
            if let id = vocabulary[wordStr] {
                tokens.append(id)
            } else {
                // Unknown token
                tokens.append(specialTokens["[UNK]"]!)
            }
        }
        
        return tokens
    }
    
    public func decode(tokens: [Int]) -> String {
        // Convert token IDs back to strings and join
        let words = tokens.map { id -> String in
            idToToken[id] ?? "[UNK]"
        }
        
        return words.joined(separator: " ")
    }
}

/// Factory for creating tokenizers based on file type
public class TokenizerFactory {
    public static func createTokenizer(path: String, type: TokenizerType) -> MLXTokenizer {
        switch type {
            case .sentencePiece:
                return SentencePieceTokenizer(modelPath: path)
            case .bpe:
                return BPETokenizer(vocabPath: path)
            case .wordPiece:
                return WordPieceTokenizer(vocabPath: path)
        }
    }
    
    public static func detectTokenizerType(filePath: String) -> TokenizerType {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent.lowercased()
        
        if fileName.contains("tokenizer.model") {
            return .sentencePiece
        } else if fileName.contains("tokenizer.json") {
            return .bpe
        } else {
            return .wordPiece
        }
    }
}
