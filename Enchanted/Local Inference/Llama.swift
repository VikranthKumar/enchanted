// Llama.swift

import Foundation
import llama

enum FeatureFlags {
    static let useLLMCaching = true
}

public enum Role {
    case user
    case bot
}

extension Token {
    enum Kind {
        case end
        case couldBeEnd
        case normal
    }
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


public enum Quantization: String {
    case IQ1_S
    case IQ1_M
    case IQ2_XXS
    case IQ2_XS
    case IQ2_S
    case IQ2_M
    case Q2_K_S
    case Q2_K
    case IQ3_XXS
    case IQ3_XS
    case IQ3_S
    case IQ3_M
    case Q3_K_S
    case Q3_K_M
    case Q3_K_L
    case IQ4_XS
    case IQ4_NL
    case Q4_0
    case Q4_1
    case Q4_K_S
    case Q4_K_M
    case Q5_0
    case Q5_1
    case Q5_K_S
    case Q5_K_M
    case Q6_K
    case Q8_0
}

extension Model {
    /// Token representing the end of sequence
//    public var endToken: Token { llama_token_eos(self) }
    
    /// Token representing a newline character
    public var newLineToken: Token { llama_token_nl(self) }
    
    /// Determines whether Beginning-of-Sequence (BOS) token should be added
    /// - Returns: True if BOS token should be added, based on model vocabulary type
    public func shouldAddBOS() -> Bool {
        let addBOS = llama_add_bos_token(self);
        guard !addBOS else {
            return llama_vocab_type(self) == LLAMA_VOCAB_TYPE_SPM
        }
        return addBOS
    }
    
    /// Decodes a single token to string without handling multibyte characters
    /// - Parameter token: The token to decode
    /// - Returns: Decoded string representation of the token
    public func decodeOnly(_ token: Token) -> String {
        var nothing: [CUnsignedChar] = []
        return decode(token, with: &nothing)
    }
    
    /// Decodes a token to string while handling multibyte characters
    /// - Parameters:
    ///   - token: The token to decode
    ///   - multibyteCharacter: Buffer for handling multibyte character sequences
    /// - Returns: Decoded string representation of the token
    public func decode(_ token: Token, with multibyteCharacter: inout [CUnsignedChar]) -> String {
        var bufferLength = 16
        var buffer: [CChar] = .init(repeating: 0, count: bufferLength)
        let actualLength = Int(llama_token_to_piece(self, token, &buffer, Int32(bufferLength), 0, false))
        guard 0 != actualLength else { return "" }
        if actualLength < 0 {
            bufferLength = -actualLength
            buffer = .init(repeating: 0, count: bufferLength)
            llama_token_to_piece(self, token, &buffer, Int32(bufferLength), 0, false)
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
    
    /// Encodes text into model tokens
    /// - Parameters:
    ///   - text: Input text to encode
    /// - Returns: Array of token IDs representing the encoded text
    /// - Note: Automatically handles BOS token addition and logs the resulting tokens for debugging
    public func encode(_ text: borrowing String) -> [Token] {
        let addBOS = true
        let count = Int32(text.cString(using: .utf8)!.count)
        var tokenCount = count + 1
        let cTokens = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(tokenCount)); defer { cTokens.deallocate() }
        tokenCount = llama_tokenize(self, text, count, cTokens, tokenCount, addBOS, false)
        let tokens = (0..<Int(tokenCount)).map { cTokens[$0] }
        
        print("Encoded tokens: \(tokens)")  // Add this line to log the resulting tokens
        
        return tokens
    }
}
