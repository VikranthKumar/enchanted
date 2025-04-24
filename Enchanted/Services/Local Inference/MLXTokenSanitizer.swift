//
//  MLXTokenSanitizer.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/5/25.
//

import Foundation

/// A utility class to process and filter tokens from MLX models
public class MLXTokenSanitizer {
    /// List of special tokens that should be filtered out
    public static let specialTokensToFilter = [
        // Basic markers
        "<s>", "</s>", "<pad>", "<eos>", "<bos>",
        
        // Llama family
        "<|im_start|>", "<|im_end|>", "<|endoftext|>",
        
        // Gemma family
        "<start_of_turn>", "<end_of_turn>",
        
        // Phi family
        "<|phi|>", "<|end|>", "<|user|>", "<|assistant|>",
        
        // Mistral family
        "<s>", "</s>", "<unk>",
        
        // BERT family
        "[CLS]", "[SEP]", "[UNK]", "[PAD]", "[MASK]",
        
        // Other problematic tokens
        "<|useruser|>", "<|assassistant|>"
    ]
    
    /// Regular expression patterns for additional token types to match
    public static let tokenPatterns = [
        // Match Phi model's placeholder tokens like <|nnoun1|>, <|datedate1|>, etc.
        "<\\|n[a-z]+\\d+\\|>",
        
        // Match any tag-like token with words and numbers
        "<\\|[a-z]+[a-z0-9]*\\|>"
    ]
    
    /// Sanitizes raw tokens from MLX before processing
    /// - Parameter token: The raw token string
    /// - Returns: A cleaned token string ready for use
    public static func sanitize(token: String) -> String {
        var sanitizedToken = token
        
        // 1. Filter out exact special tokens
        if specialTokensToFilter.contains(token) {
            return ""
        }
        
        // 2. Filter out special token patterns with regex
        for pattern in tokenPatterns {
            sanitizedToken = sanitizedToken.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        
        // 3. Remove BOS/EOS tags
        sanitizedToken = sanitizedToken.replacingOccurrences(of: "^<s>|</s>$", with: "", options: .regularExpression)
        
        // 4. Remove any remaining XML-like tags with words inside
        sanitizedToken = sanitizedToken.replacingOccurrences(of: "<\\|[^\\|]+\\|>", with: "", options: .regularExpression)
        
        // 5. Filter control characters, keeping only printable chars, newlines, and tabs
        sanitizedToken = sanitizedToken.filter { char in
            let isVisibleASCII = char.isASCII && char.isPrintable
            let isAllowedControl = char == "\n" || char == "\t"
            return isVisibleASCII || isAllowedControl || !char.isASCII
        }
        
        // 6. Handle UTF-8 encoding issues (if any)
        if let data = sanitizedToken.data(using: .utf8),
           let validUTF8String = String(data: data, encoding: .utf8) {
            sanitizedToken = validUTF8String
        }
        
        // 7. Remove specific unwanted characters
        sanitizedToken = sanitizedToken.replacingOccurrences(of: "◆", with: "")
        
        return sanitizedToken
    }
    
    /// Check if a token contains any of our filtered patterns
    public static func containsFilteredToken(_ text: String) -> Bool {
        // Check exact matches
        for token in specialTokensToFilter {
            if text.contains(token) {
                return true
            }
        }
        
        // Check regex patterns
        for pattern in tokenPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Clean up a full text response
    public static func cleanResponse(_ text: String) -> String {
        var cleaned = text
        
        // Remove any special tokens
        for token in specialTokensToFilter {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        
        // Apply regex cleaning
        for pattern in tokenPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        
        // Remove any leftover XML-like tags
        cleaned = cleaned.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // Collapse multiple newlines
        cleaned = cleaned.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}

extension Character {
    /// Determines if a character is printable (visible when displayed)
    var isPrintable: Bool {
        // ASCII printable range is 32-126 (space to tilde)
        if let asciiValue = self.asciiValue {
            return (asciiValue >= 32 && asciiValue <= 126) || asciiValue == 9 || asciiValue == 10 || asciiValue == 13
        }
        // Non-ASCII characters are considered printable
        return true
    }
}
