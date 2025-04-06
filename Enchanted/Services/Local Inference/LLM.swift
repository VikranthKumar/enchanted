//
//  LLM.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/5/25.
//

import Foundation
import llama

public typealias Token = llama_token
public typealias Model = OpaquePointer

public struct Chat: Identifiable, Equatable {
    public var id: UUID?
    public var role: Role
    public var content: String
    
    public init(id: UUID? = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

@globalActor public actor InferenceActor {
    static public let shared = InferenceActor()
}

open class LLM: ObservableObject {
    // Core properties
    public var model: Model
    public var history: [Chat]
    public var preprocess: (_ input: String, _ history: [Chat], _ llmInstance: LLM) -> String = { input, _, _ in return input }
    public var postprocess: (_ output: String) -> Void = { _ in }
    public var update: (_ outputDelta: String?) -> Void = { _ in }
    public var template: Template? = nil {
        didSet {
            guard let template else {
                preprocess = { input, _, _ in return input }
                stopSequence = nil
                stopSequenceLength = 0
                return
            }
            preprocess = template.preprocess
            if let stopSequence = template.stopSequence?.utf8CString {
                self.stopSequence = stopSequence
                stopSequenceLength = stopSequence.count - 1
            } else {
                stopSequence = nil
                stopSequenceLength = 0
            }
        }
    }
    
    // Sampling parameters
    public var topK: Int32
    public var topP: Float
    public var temp: Float
    
    // State tracking
    public var path: [CChar]
    public var savedState: Data?
    var metrics = InferenceMetrics()
    @Published public private(set) var output = ""
    
    // Internal state
    private var batch: llama_batch!
    private var context: Context!
    private var inferenceTask: Task<Void, Never>?
    private var input: String = ""
    private let newlineToken: Token
    private let maxTokenCount: Int
    private var multibyteCharacter: [CUnsignedChar] = []
    private var params: llama_context_params
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var stopSequence: ContiguousArray<CChar>?
    private var stopSequenceLength: Int
    private let totalTokenCount: Int
    private var nPast: Int32 = 0
    private var inputTokenCount: Int32 = 0
    
    public init(
        from path: String,
        stopSequence: String? = nil,
        history: [Chat] = [],
        seed: UInt32 = .random(in: .min ... .max),
        topK: Int32 = 40,
        topP: Float = 0.95,
        temp: Float = 0.8,
        maxTokenCount: Int32 = 2048
    ) {
        self.path = path.cString(using: .utf8)!
        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#endif
        
        // Safely load the model and handle errors
        guard let model = llama_load_model_from_file(self.path, modelParams) else {
            fatalError("Failed to load model from path: \(path). Please check that the file exists and is a valid GGUF format.")
        }
        
        self.params = llama_context_default_params()
        let processorCount = Int32(ProcessInfo().processorCount)
        self.maxTokenCount = Int(min(maxTokenCount, llama_n_ctx_train(model)))
        self.params.n_ctx = UInt32(self.maxTokenCount)
        self.params.n_batch = self.params.n_ctx
        self.params.n_threads = processorCount
        self.params.n_threads_batch = processorCount
        self.topK = topK
        self.topP = topP
        self.temp = temp
        self.model = model
        self.history = history
        self.totalTokenCount = Int(llama_n_vocab(model))
        self.newlineToken = llama_token_nl(model)
        self.stopSequence = stopSequence?.utf8CString
        self.stopSequenceLength = (self.stopSequence?.count ?? 1) - 1
        self.batch = llama_batch_init(Int32(self.maxTokenCount), 0, 1)
        
        // Initialize sampler
        let sparams = llama_sampler_chain_default_params()
        self.sampler = llama_sampler_chain_init(sparams)
        
        if let sampler = self.sampler {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(topK))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(topP, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temp))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed))
        }
    }
    
    deinit {
        llama_free_model(self.model)
    }
    
    public convenience init(
        from url: URL,
        template: Template,
        history: [Chat] = [],
        seed: UInt32 = .random(in: .min ... .max),
        topK: Int32 = 40,
        topP: Float = 0.95,
        temp: Float = 0.8,
        maxTokenCount: Int32 = 2048
    ) {
        self.init(
            from: url.path,
            stopSequence: template.stopSequence,
            history: history,
            seed: seed,
            topK: topK,
            topP: topP,
            temp: temp,
            maxTokenCount: maxTokenCount
        )
        self.preprocess = template.preprocess
        self.template = template
    }
    
    @MainActor public func setOutput(to newOutput: String) {
        output = newOutput.trimmingCharacters(in: .whitespaces)
    }
    
    @InferenceActor
    public func stop() {
        guard self.inferenceTask != nil else { return }
        self.inferenceTask?.cancel()
        self.inferenceTask = nil
        self.batch.clear()
    }
    
    @InferenceActor
    private func predictNextToken() async -> Token {
        guard let context = self.context else { return llama_token_eos(self.model) }
        guard !Task.isCancelled else { return llama_token_eos(self.model) }
        guard self.inferenceTask != nil else { return llama_token_eos(self.model) }
        guard self.batch.n_tokens > 0 else {
            return llama_token_eos(self.model)
        }
        guard self.batch.n_tokens < self.maxTokenCount else {
            return llama_token_eos(self.model)
        }
        guard let sampler = self.sampler else {
            fatalError("Sampler not initialized")
        }
        
        let token = llama_sampler_sample(sampler, context.pointer, self.batch.n_tokens - 1)
        metrics.recordToken()
        
        self.batch.clear()
        self.batch.add(token, self.nPast, [0], true)
        self.nPast += 1
        context.decode(self.batch)
        return token
    }
    
    @InferenceActor
    public func clearHistory() async {
        history.removeAll()
        nPast = 0
        await setOutput(to: "")
        context = nil
        savedState = nil
        self.batch.clear()
    }
    
    @InferenceActor
    private func tokenizeAndBatchInput(message input: String) -> Bool {
        guard self.inferenceTask != nil else { return false }
        guard !input.isEmpty else { return false }
        context = context ?? .init(model, params)
        let tokens = encode(input)
        self.inputTokenCount = Int32(tokens.count)
        metrics.inputTokenCount = self.inputTokenCount
        
        if self.maxTokenCount <= self.nPast + self.inputTokenCount {
            self.trimKvCache()
        }
        
        for (i, token) in tokens.enumerated() {
            let isLastToken = i == tokens.count - 1
            self.batch.add(token, self.nPast, [0], isLastToken)
            nPast += 1
        }
        
        guard self.batch.n_tokens > 0 else { return false }
        self.context.decode(self.batch)
        return true
    }
    
    @InferenceActor
    private func emitDecoded(token: Token, to output: AsyncStream<String>.Continuation) -> Bool {
        struct saved {
            static var stopSequenceEndIndex = 0
            static var letters: [CChar] = []
        }
        
        guard self.inferenceTask != nil else { return false }
        guard token != llama_token_eos(model) else { return false }
        
        let word = decode(token)
        
        guard let stopSequence else {
            output.yield(word)
            return true
        }
        
        var found = 0 < saved.stopSequenceEndIndex
        var letters: [CChar] = []
        
        for letter in word.utf8CString {
            guard letter != 0 else { break }
            if letter == stopSequence[saved.stopSequenceEndIndex] {
                saved.stopSequenceEndIndex += 1
                found = true
                saved.letters.append(letter)
                guard saved.stopSequenceEndIndex == stopSequenceLength else { continue }
                saved.stopSequenceEndIndex = 0
                saved.letters.removeAll()
                return false
            } else if found {
                saved.stopSequenceEndIndex = 0
                if !saved.letters.isEmpty {
                    let prefix = String(cString: saved.letters + [0])
                    output.yield(prefix + word)
                    saved.letters.removeAll()
                }
                output.yield(word)
                return true
            }
            letters.append(letter)
        }
        
        if !letters.isEmpty {
            output.yield(found ? String(cString: letters + [0]) : word)
        }
        
        return true
    }
    
    @InferenceActor
    private func generateResponseStream(from input: String) -> AsyncStream<String> {
        AsyncStream<String> { output in
            Task { [weak self] in
                guard let self = self else { return output.finish() }
                guard self.inferenceTask != nil else { return output.finish() }
                
                guard self.tokenizeAndBatchInput(message: input) else {
                    return output.finish()
                }
                
                metrics.start()
                var token = await self.predictNextToken()
                while self.emitDecoded(token: token, to: output) {
                    if self.nPast >= self.maxTokenCount {
                        self.trimKvCache()
                    }
                    token = await self.predictNextToken()
                }
                
                metrics.stop()
                output.finish()
            }
        }
    }
    
    @InferenceActor
    private func trimKvCache() {
        let seq_id: Int32 = 0
        let beginning: Int32 = 0
        let middle = Int32(self.maxTokenCount / 2)
        
        llama_kv_cache_seq_rm(self.context.pointer, seq_id, beginning, middle)
        llama_kv_cache_seq_add(
            self.context.pointer,
            seq_id,
            middle,
            Int32(self.maxTokenCount), -middle
        )
        
        let kvCacheTokenCount: Int32 = llama_get_kv_cache_token_count(self.context.pointer)
        self.nPast = kvCacheTokenCount
    }
    
    @InferenceActor
    public func performInference(to input: String, with makeOutputFrom: @escaping (AsyncStream<String>) async -> String) async {
        self.inferenceTask?.cancel()
        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }
            
            self.input = input
            let processedInput = self.preprocess(input, self.history, self)
            let responseStream = self.generateResponseStream(from: processedInput)
            
            let output = (await makeOutputFrom(responseStream)).trimmingCharacters(in: .whitespacesAndNewlines)
            
            await MainActor.run {
                if !output.isEmpty {
                    self.history.append(Chat(role: .bot, content: output))
                }
                self.postprocess(output)
            }
            
            self.inputTokenCount = 0
            self.savedState = saveState()
            
            if Task.isCancelled {
                return
            }
        }
        
        await inferenceTask?.value
    }
    
    open func respond(to input: String) async {
        if let savedState = self.savedState {
            restoreState(from: savedState)
        }
        
        await performInference(to: input) { [self] response in
            await setOutput(to: "")
            for await responseDelta in response {
                update(responseDelta)
                await setOutput(to: output + responseDelta)
            }
            update(nil)
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedOutput.isEmpty && self.inputTokenCount > 0 {
                let seq_id = Int32(0)
                let startIndex = self.nPast - self.inputTokenCount
                let endIndex = self.nPast
                llama_kv_cache_seq_rm(self.context.pointer, seq_id, startIndex, endIndex)
            }
            
            await setOutput(to: trimmedOutput.isEmpty ? "..." : trimmedOutput)
            return output
        }
    }
    
    private func decode(_ token: Token) -> String {
        multibyteCharacter.removeAll(keepingCapacity: true)
        var bufferLength = 16
        var buffer: [CChar] = .init(repeating: 0, count: bufferLength)
        let actualLength = Int(llama_token_to_piece(self.model, token, &buffer, Int32(bufferLength), 0, false))
        
        guard 0 != actualLength else { return "" }
        
        if actualLength < 0 {
            bufferLength = -actualLength
            buffer = .init(repeating: 0, count: bufferLength)
            llama_token_to_piece(self.model, token, &buffer, Int32(bufferLength), 0, false)
        } else {
            buffer.removeLast(bufferLength - actualLength)
        }
        
        if multibyteCharacter.isEmpty, let decoded = String(cString: buffer + [0], encoding: .utf8) {
            return decoded
        }
        
        multibyteCharacter.append(contentsOf: buffer.map { CUnsignedChar(bitPattern: $0) })
        
        guard let decoded = String(data: .init(multibyteCharacter), encoding: .utf8) else { return "" }
        
        multibyteCharacter.removeAll(keepingCapacity: true)
        return decoded
    }
    
    public func encode(_ text: String) -> [Token] {
        let addBOS = true
        let count = Int32(text.cString(using: .utf8)!.count)
        var tokenCount = count + 1
        let cTokens = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(tokenCount))
        defer { cTokens.deallocate() }
        
        tokenCount = llama_tokenize(self.model, text, count, cTokens, tokenCount, addBOS, false)
        return (0..<Int(tokenCount)).map { cTokens[$0] }
    }
    
    public func saveState() -> Data? {
        guard let contextPointer = self.context?.pointer else {
            return nil
        }
        
        let stateSize = llama_state_get_size(contextPointer)
        guard stateSize > 0 else {
            return nil
        }
        
        var stateData = Data(count: stateSize)
        stateData.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) in
            if let baseAddress = pointer.baseAddress {
                llama_state_get_data(contextPointer, baseAddress.assumingMemoryBound(to: UInt8.self), stateSize)
            }
        }
        return stateData
    }
    
    public func restoreState(from stateData: Data) {
        guard let contextPointer = self.context?.pointer else {
            return
        }
        
        stateData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            if let baseAddress = pointer.baseAddress {
                llama_state_set_data(contextPointer, baseAddress.assumingMemoryBound(to: UInt8.self), stateData.count)
            }
        }
        
        self.nPast = llama_get_kv_cache_token_count(self.context.pointer) + 1
    }
}
