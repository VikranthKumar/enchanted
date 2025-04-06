//
//  Llama.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/5/25.
//

import Foundation
import llama

enum FeatureFlags {
    static let useLLMCaching = true
}

public enum Role {
    case user
    case bot
}

public class Context {
    let pointer: OpaquePointer
    
    init(_ model: Model, _ params: llama_context_params) {
        self.pointer = llama_new_context_with_model(model, params)
    }
    
    deinit {
        llama_free(pointer)
    }
    
    func decode(_ batch: llama_batch) {
        let ret = llama_decode(pointer, batch)
        
        if ret < 0 {
            fatalError("llama_decode failed: \(ret)")
        } else if ret > 0 {
            print("llama_decode returned \(ret)")
        }
    }
}

extension llama_batch {
    mutating func clear() {
        self.n_tokens = 0
    }
    
    mutating func add(_ token: Token, _ position: Int32, _ ids: [Int], _ logit: Bool) {
        let i = Int(self.n_tokens)
        self.token[i] = token
        self.pos[i] = position
        self.n_seq_id[i] = Int32(ids.count)
        if let seq_id = self.seq_id[i] {
            for (j, id) in ids.enumerated() {
                seq_id[j] = Int32(id)
            }
        }
        self.logits[i] = logit ? 1 : 0
        self.n_tokens += 1
    }
}

extension String {
    var utf8CString: ContiguousArray<CChar> {
        var result = ContiguousArray<CChar>()
        self.withCString { ptr in
            var index = 0
            while ptr[index] != 0 {
                result.append(ptr[index])
                index += 1
            }
        }
        return result
    }
}

struct InferenceMetrics {
    var inputTokenCount: Int32 = 0
    var outputTokenCount: Int32 = 0
    var startTime: Date?
    var endTime: Date?
    
    mutating func start() {
        startTime = Date()
        outputTokenCount = 0
    }
    
    mutating func stop() {
        endTime = Date()
    }
    
    mutating func recordToken() {
        outputTokenCount += 1
    }
    
    var elapsedTime: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var tokensPerSecond: Double? {
        guard let elapsed = elapsedTime, elapsed > 0 else { return nil }
        return Double(outputTokenCount) / elapsed
    }
}
