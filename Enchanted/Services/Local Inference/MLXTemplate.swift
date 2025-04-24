//
//  MLXTemplate.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/5/25.
//

import Foundation

/// A structure that defines how to format conversations for different LLM architectures
public struct MLXTemplate {
    /// Represents prefix and suffix text to wrap around different message types
    public typealias Attachment = (prefix: String, suffix: String)
    
    /// Formatting for system messages
    public let system: Attachment
    
    /// Formatting for user messages
    public let user: Attachment
    
    /// Formatting for bot/assistant messages
    public let bot: Attachment
    
    /// Optional system prompt to set context for the conversation
    public var systemPrompt: String?
    
    /// Sequence that indicates the end of the model's response
    public let stopSequence: String?
    
    /// Text to prepend to the entire conversation
    public let prefix: String
    
    /// Whether to drop the last character of the bot prefix
    public let shouldDropLast: Bool
    
    /// Creates a new template for formatting conversation messages
    public init(
        prefix: String = "",
        system: Attachment? = nil,
        user: Attachment? = nil,
        bot: Attachment? = nil,
        stopSequence: String? = nil,
        systemPrompt: String? = nil,
        shouldDropLast: Bool = false
    ) {
        self.system = system ?? ("", "")
        self.user = user ?? ("", "")
        self.bot = bot ?? ("", "")
        self.stopSequence = stopSequence
        self.systemPrompt = systemPrompt
        self.prefix = prefix
        self.shouldDropLast = shouldDropLast
    }
    
    /// Formats input and history into model-ready prompt
    public func preprocess(input: String, history: [MLXMessage], hasState: Bool) -> String {
        if hasState {
            // Return only the new user input formatted
            var processed = prefix
            processed += "\(user.prefix)\(input)\(user.suffix)"
            processed += bot.prefix
            return processed
        } else {
            // Full preprocessing for the first input or reset state
            var processed = prefix
            if let systemPrompt = systemPrompt {
                processed += "\(system.prefix)\(systemPrompt)\(system.suffix)"
            }
            for chat in history {
                if chat.role == .user {
                    processed += "\(user.prefix)\(chat.content)\(user.suffix)"
                } else if chat.role == .bot {
                    processed += "\(bot.prefix)\(chat.content)\(bot.suffix)"
                } else if chat.role == .system {
                    processed += "\(system.prefix)\(chat.content)\(system.suffix)"
                }
            }
            // Add the current user input
            processed += "\(user.prefix)\(input)\(user.suffix)"
            // Handle bot prefix for the new response
            if shouldDropLast && !bot.prefix.isEmpty {
                processed += String(bot.prefix.dropLast())
            } else {
                processed += bot.prefix
            }
            return processed
        }
    }
    
    /// Creates a template for ChatML format (for Llama 3 models)
    public static func chatML(_ systemPrompt: String? = nil) -> MLXTemplate {
        return MLXTemplate(
            system: ("<|im_start|>system\n", "<|im_end|>\n"),
            user: ("<|im_start|>user\n", "<|im_end|>\n"),
            bot: ("<|im_start|>assistant\n", "<|im_end|>\n"),
            stopSequence: "<|im_end|>",
            systemPrompt: systemPrompt
        )
    }
    
    /// Creates a template for LLaMA 2-style models
    public static func llama2(_ systemPrompt: String? = nil) -> MLXTemplate {
        return MLXTemplate(
            prefix: "[INST] ",
            system: ("<<SYS>>\n", "\n<</SYS>>\n\n"),
            user: ("", " [/INST]"),
            bot: (" ", "</s><s>[INST] "),
            stopSequence: "</s>",
            systemPrompt: systemPrompt,
            shouldDropLast: true
        )
    }
    
    /// Template configured for Mistral-style models
    public static let mistral = MLXTemplate(
        user: ("[INST] ", " [/INST]"),
        bot: ("", "</s> "),
        stopSequence: "</s>",
        systemPrompt: nil
    )
    
    /// Template for Phi models
    public static func phi(_ systemPrompt: String? = nil) -> MLXTemplate {
        return MLXTemplate(
            system: ("<|system|>\n", "\n"),
            user: ("<|user|>\n", "\n"),
            bot: ("<|assistant|>\n", "\n"),
            stopSequence: "<|end|>",
            systemPrompt: systemPrompt
        )
    }
    
    /// Template for Gemma models
    public static func gemma(_ systemPrompt: String? = nil) -> MLXTemplate {
        return MLXTemplate(
            system: ("<start_of_turn>system\n", "<end_of_turn>\n"),
            user: ("<start_of_turn>user\n", "<end_of_turn>\n"),
            bot: ("<start_of_turn>model\n", "<end_of_turn>\n"),
            stopSequence: "<end_of_turn>",
            systemPrompt: systemPrompt
        )
    }
}

/// Factory for creating templates based on model architecture
public class TemplateFactory {
    public static func createTemplate(for architecture: ModelArchitecture, systemPrompt: String? = nil) -> MLXTemplate {
        switch architecture {
            case .llama:
                return MLXTemplate.chatML(systemPrompt)
            case .phi:
                return MLXTemplate.phi(systemPrompt)
            case .gemma:
                return MLXTemplate.gemma(systemPrompt)
            case .mistral:
                return MLXTemplate.mistral
            case .unknown:
                // Default template for unknown models
                return MLXTemplate(
                    user: ("USER: ", "\n"),
                    bot: ("ASSISTANT: ", "\n\n"),
                    stopSequence: "USER:",
                    systemPrompt: systemPrompt
                )
        }
    }
    
    public static func createTemplate(for promptFormat: ModelPromptFormat, systemPrompt: String? = nil) -> MLXTemplate {
        switch promptFormat {
            case .llama3:
                return MLXTemplate.chatML(systemPrompt)
            case .llama2:
                return MLXTemplate.llama2(systemPrompt)
            case .phi:
                return MLXTemplate.phi(systemPrompt)
            case .gemma:
                return MLXTemplate.gemma(systemPrompt)
            case .mistral:
                return MLXTemplate.mistral
        }
    }
}
