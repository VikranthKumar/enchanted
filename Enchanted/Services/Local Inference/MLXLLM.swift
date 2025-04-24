//
//  MLXLLM.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/5/25.
//

import Foundation
import MLX
import Combine
import SwiftUI

/// Global actor for MLX inference to ensure sequential processing
@globalActor public actor MLXInferenceActor {
    public static let shared = MLXInferenceActor()
}

/// Main LLM implementation using MLX
public class MLXLLM: ObservableObject {
    // Model components
    private let model: [String: MLXArray]
    private let tokenizer: MLXTokenizer
    private let configDict: [String: Any]
    
    // Model template
    public var template: MLXTemplate
    
    // Conversation history
    public var history: [MLXMessage] = []
    
    // Generation parameters
    public var topK: Int
    public var topP: Float
    public var temperature: Float
    public var maxTokenCount: Int
    
    // State tracking
    @Published public private(set) var output: String = ""
    @Published public private(set) var isGenerating: Bool = false
    public private(set) var savedState: Data?
    
    // Metrics
    public var metrics = InferenceMetrics()
    
    // Callbacks
    public var updateCallback: ((String?) -> Void)? = nil
    
    // Cache for KV values
    private var kvCache: [String: MLXArray] = [:]
    private var inferenceTask: Task<Void, Never>?
    
    /// Initialize the model
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - tokenizerPath: Path to the tokenizer file
    ///   - architecture: Model architecture
    ///   - config: Additional configuration parameters
    ///   - systemPrompt: Optional system prompt to set context
    ///   - seed: Random seed for reproducibility
    ///   - topK: Top-K sampling parameter
    ///   - topP: Top-P sampling parameter
    ///   - temperature: Temperature for sampling
    ///   - maxTokenCount: Maximum token count for generation
    public init(
        modelPath: String,
        tokenizerPath: String,
        architecture: ModelArchitecture,
        config: [String: Any]? = nil,
        systemPrompt: String? = nil,
        seed: UInt32 = UInt32.random(in: .min ... .max),
        topK: Int = 40,
        topP: Float = 0.95,
        temperature: Float = 0.8,
        maxTokenCount: Int = 2048
    ) throws {
        // Load the model
        print("Loading MLX model from \(modelPath)")
        let modelData = try Data(contentsOf: URL(fileURLWithPath: modelPath))
        
        // Create configuration or use provided one
        let mergedConfig: [String: Any]
        if let config = config {
            mergedConfig = config
        } else {
            mergedConfig = [
                "temperature": temperature,
                "top_k": topK,
                "top_p": topP,
                "max_tokens": maxTokenCount
            ]
        }
        
        // Load model weights
        // In a real implementation, we would use MLX.loadWeights or similar
        // For now, create some dummy tensors
        self.model = [
            "embedding.weight": MLXArray.zeros([32000, 768]),
            "attention.weight": MLXArray.zeros([768, 768]),
            "mlp.weight": MLXArray.zeros([768, 3072])
        ]
        
        // Store config
        self.configDict = mergedConfig
        
        // Determine tokenizer type
        let tokenizerType = TokenizerFactory.detectTokenizerType(filePath: tokenizerPath)
        
        // Load tokenizer
        self.tokenizer = TokenizerFactory.createTokenizer(path: tokenizerPath, type: tokenizerType)
        
        // Create template based on architecture
        self.template = TemplateFactory.createTemplate(for: architecture, systemPrompt: systemPrompt)
        
        // Set generation parameters
        self.topK = topK
        self.topP = topP
        self.temperature = temperature
        self.maxTokenCount = maxTokenCount
        
        // Set random seed
        MLX.seed(UInt64(Int(seed)))
    }
    
    /// Initialize with prompt format
    public convenience init(
        modelPath: String,
        tokenizerPath: String,
        promptFormat: ModelPromptFormat,
        systemPrompt: String? = nil,
        seed: UInt32 = UInt32.random(in: .min ... .max),
        topK: Int = 40,
        topP: Float = 0.95,
        temperature: Float = 0.8,
        maxTokenCount: Int = 2048
    ) throws {
        // Map prompt format to architecture
        let architecture: ModelArchitecture
        switch promptFormat {
            case .llama3, .llama2:
                architecture = .llama
            case .phi:
                architecture = .phi
            case .gemma:
                architecture = .gemma
            case .mistral:
                architecture = .mistral
        }
        
        try self.init(
            modelPath: modelPath,
            tokenizerPath: tokenizerPath,
            architecture: architecture,
            systemPrompt: systemPrompt,
            seed: seed,
            topK: topK,
            topP: topP,
            temperature: temperature,
            maxTokenCount: maxTokenCount
        )
    }
    
    @MainActor
    public func setOutput(to newOutput: String) {
        output = newOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MLXInferenceActor
    public func stop() {
        inferenceTask?.cancel()
        inferenceTask = nil
        isGenerating = false
    }
    
    @MLXInferenceActor
    public func clearHistory() async {
        history.removeAll()
        await setOutput(to: "")
        savedState = nil
        kvCache.removeAll()
    }
    
    /// Encode text to token IDs
    @MLXInferenceActor
    private func encode(_ text: String, addBos: Bool = true) -> [Int] {
        return tokenizer.encode(text: text, addBos: addBos)
    }
    
    /// Decode token IDs to text
    @MLXInferenceActor
    private func decode(_ tokens: [Int]) -> String {
        return tokenizer.decode(tokens: tokens)
    }
    
    /// Check if tokens match the stop sequence
    @MLXInferenceActor
    private func checkForStopSequence(tokens: [Int]) -> Bool {
        guard let stopSequence = template.stopSequence else { return false }
        
        // Encode the stop sequence
        let stopTokens = tokenizer.encode(text: stopSequence, addBos: false)
        
        // Check if tokens end with the stop sequence
        if tokens.count >= stopTokens.count {
            let lastTokens = Array(tokens.suffix(stopTokens.count))
            return lastTokens == stopTokens
        }
        
        return false
    }
    
    /// Generate the next token using the model
    @MLXInferenceActor
    private func generateNextToken(from tokens: [Int]) async -> Int? {
        guard !Task.isCancelled else { return nil }
        
        // Convert tokens to MLX arrays
        let inputArray = MLXArray(tokens)
        
        // Prepare inputs
        var inputs: [String: MLXArray] = [
            "input_ids": inputArray
        ]
        
        // Add KV cache if available
        if !kvCache.isEmpty {
            for (key, value) in kvCache {
                inputs[key] = value
            }
        }
        
        // Run the model
        do {
            // This would be a real MLX inference call
            // For now, create a mock response
            // let output = try MLX.run(model: model, inputs: inputs)
            
            // Create a dummy logits array
            let batchSize = 1
            let vocabSize = 32000
            let logits = MLXArray.random([batchSize, vocabSize])
            
            // Apply temperature
            let scaledLogits = logits / MLXArray.scalar(Double(temperature))
            
            // Apply top-k filtering
            let topKLogits = MLXLLM.topK(tensor: scaledLogits, k: topK)
            
            // Apply top-p sampling
            let sampledToken = MLXLLM.sample(tensor: topKLogits, p: topP)
            
            // Update KV cache
            // In a real implementation, we would extract cache from the model output
            // kvCache = output["cache"] as? [String: MLXArray] ?? [:]
            
            metrics.recordToken()
            
            return sampledToken
        } catch {
            print("Error generating token: \(error)")
            return nil
        }
    }
    
    /// Generate a stream of text from the model
    @MLXInferenceActor
    private func generateResponseStream(from input: String) -> AsyncStream<String> {
        AsyncStream<String> { continuation in
            Task { [weak self] in
                guard let self = self else { return continuation.finish() }
                guard !Task.isCancelled else { return continuation.finish() }
                
                // Get preprocessed input
                let processedInput = template.preprocess(
                    input: input,
                    history: history,
                    hasState: savedState != nil
                )
                
                // Tokenize input
                let inputTokens = encode(processedInput)
                
                // Start metrics tracking
                metrics.start()
                metrics.inputTokenCount = Int32(inputTokens.count)
                
                // Begin token generation loop
                var generatedTokens: [Int] = []
                var lastText = ""
                
                isGenerating = true
                
                while generatedTokens.count < self.maxTokenCount {
                    // Check if task is cancelled
                    if Task.isCancelled {
                        break
                    }
                    
                    // Generate next token
                    let context = inputTokens + generatedTokens
                    guard let nextToken = await self.generateNextToken(from: context) else {
                        break
                    }
                    
                    // Add token to generated sequence
                    generatedTokens.append(nextToken)
                    
                    // Check for stop sequence
                    if self.checkForStopSequence(tokens: generatedTokens) {
                        // Remove the stop sequence from the output
                        if let stopSequence = template.stopSequence,
                           let stopTokens = try? tokenizer.encode(text: stopSequence, addBos: false) {
                            generatedTokens.removeLast(stopTokens.count)
                        }
                        break
                    }
                    
                    // Decode current tokens and emit difference
                    let text = self.decode(generatedTokens)
                    if text != lastText {
                        let sanitizedText = MLXTokenSanitizer.sanitize(token: String(text.dropFirst(lastText.count)))
                        if !sanitizedText.isEmpty {
                            continuation.yield(sanitizedText)
                        }
                        lastText = text
                    }
                }
                
                metrics.stop()
                isGenerating = false
                continuation.finish()
            }
        }
    }
    
    /// Run inference to generate a response
    @MLXInferenceActor
    public func performInference(to input: String, with makeOutputFrom: @escaping (AsyncStream<String>) async -> String) async {
        self.inferenceTask?.cancel()
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }
            
            let responseStream = self.generateResponseStream(from: input)
            
            let output = (await makeOutputFrom(responseStream)).trimmingCharacters(in: .whitespacesAndNewlines)
            
            await MainActor.run {
                if !output.isEmpty {
                    self.history.append(MLXMessage(role: .bot, content: output))
                }
                
                // Call the update callback with nil to indicate completion
                self.updateCallback?(nil)
            }
            
            self.savedState = saveState()
            
            if Task.isCancelled {
                return
            }
        }
        
        await inferenceTask?.value
    }
    
    /// Generate a response to the given input
    public func respond(to input: String) async {
        if let savedState = self.savedState {
            restoreState(from: savedState)
        }
        
        await performInference(to: input) { [weak self] response in
            guard let self = self else { return "" }
            
            await setOutput(to: "")
            
            for await responseDelta in response {
                // Update callback with the delta
                self.updateCallback?(responseDelta)
                
                // Update the output
                await setOutput(to: output + responseDelta)
            }
            
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            await setOutput(to: trimmedOutput.isEmpty ? "..." : trimmedOutput)
            
            return output
        }
    }
    
    /// Save the model state
    public func saveState() -> Data? {
        // Serialize the KV cache and other state
        // This would be a real implementation in a production system
        // For now, just create a dummy state
        let state: [String: Any] = [
            "kv_cache_present": !kvCache.isEmpty
        ]
        
        return try? JSONSerialization.data(withJSONObject: state)
    }
    
    /// Restore the model state
    public func restoreState(from stateData: Data) {
        // Deserialize and restore state
        guard let state = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] else {
            return
        }
        
        // In a real implementation, we would restore the KV cache
        // For now, just print that we're restoring state
        print("Restoring model state: \(state)")
    }
}

// MARK: - MLX Extensions

extension MLXArray {
    /// Create an MLXArray from an array of integers
    convenience init(_ values: [Int]) {
        // In a real implementation, this would create an MLXArray from the values
        // For now, create an empty array
        self.init()
    }
    
    /// Create a random MLXArray with the given shape
    static func random(_ shape: [Int]) -> MLXArray {
        // In a real implementation, this would create a random MLXArray
        // For now, create an empty array
        return MLXArray()
    }
    
    /// Create a scalar MLXArray
    static func scalar(_ value: Double) -> MLXArray {
        // In a real implementation, this would create a scalar MLXArray
        // For now, create an empty array
        return MLXArray()
    }
    
    /// Zeros array with given shape
    static func zeros(_ shape: [Int]) -> MLXArray {
        // In a real implementation, this would create an MLXArray filled with zeros
        // For now, create an empty array
        return MLXArray()
    }
}

extension MLXLLM {
    /// Set the random seed
    static func seed(_ seed: Int) {
        // In a real implementation, this would set the random seed
        print("Setting MLX random seed to \(seed)")
    }
    
    /// Apply top-k filtering
    static func topK(tensor: MLXArray, k: Int) -> MLXArray {
        // In a real implementation, this would apply top-k filtering
        // For now, return the input
        return tensor
    }
    
    /// Sample from a distribution
    static func sample(tensor: MLXArray, p: Float) -> Int {
        // In a real implementation, this would sample from the distribution
        // For now, return a random token
        return Int.random(in: 0..<10)
    }
}
