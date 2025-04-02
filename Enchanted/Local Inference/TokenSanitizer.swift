//
//  TokenSanitizer.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/2/25.
//

import Foundation

/// A class to process and filter tokens from local inference models
class TokenSanitizer {
    
    /// Sanitizes raw tokens from llama.cpp before processing
    /// - Parameter token: The raw token string from llama.cpp
    /// - Returns: A cleaned token string ready for use
    static func sanitize(token: String) -> String {
        var sanitizedToken = token
        
        // 1. Handle special tokens that might come from the model
        if token == "<s>" || token == "</s>" || token == "<pad>" {
            return ""
        }
        
        // 2. Remove any BOS (Beginning of Sequence) or EOS (End of Sequence) tokens
        sanitizedToken = sanitizedToken.replacingOccurrences(of: "^<s>|</s>$", with: "", options: .regularExpression)
        
        // 3. Handle potential control characters
        sanitizedToken = sanitizedToken.filter { char in
            // Allow only printable characters, newlines, and tabs
            let isVisibleASCII = char.isASCII && char.isPrintable
            let isAllowedControl = char == "\n" || char == "\t"
            return isVisibleASCII || isAllowedControl || !char.isASCII
        }
        
        // 4. Handle UTF-8 encoding issues
        if let data = sanitizedToken.data(using: .utf8),
           let validUTF8String = String(data: data, encoding: .utf8) {
            sanitizedToken = validUTF8String
        }
        
        // 5. IMPORTANT: Remove the diamond (◆) character specifically
        sanitizedToken = sanitizedToken.replacingOccurrences(of: "◆", with: "")
        
        return sanitizedToken
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
