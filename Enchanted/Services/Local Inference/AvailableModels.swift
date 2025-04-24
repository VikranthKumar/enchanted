//
//  AvailableModels.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/2/25.
//

import Foundation

// Predefined models
extension MLXLocalModelService {
    // List of available models for download
    static let availableModels = [
        MLXModelDownloadInfo(
            name: "mlx-tinyllama-1.1b",
            displayName: "TinyLlama 1.1B (MLX)",
            url: URL(string: "https://huggingface.co/mlx-community/tinyllama-1.1b-mlx/resolve/main/tinyllama-1.1b-mlx.safetensors")!,
            fileExtension: "gguf",
            tokenizerURL: URL(string: "https://huggingface.co/mlx-community/tinyllama-1.1b-mlx/resolve/main/tokenizer.model")!,
            size: "550 MB",
            promptFormat: .llama3
        ),
        MLXModelDownloadInfo(
            name: "mlx-phi-2",
            displayName: "Phi-2 (MLX)",
            url: URL(string: "https://huggingface.co/mlx-community/phi-2-mlx/resolve/main/phi-2-mlx.safetensors")!,
            fileExtension: "gguf",
            tokenizerURL: URL(string: "https://huggingface.co/mlx-community/phi-2-mlx/resolve/main/tokenizer.json")!,
            size: "1.1 GB",
            promptFormat: .phi
        ),
        MLXModelDownloadInfo(
            name: "mlx-gemma-3-1b",
            displayName: "Gemma 3 1B (MLX)",
            url: URL(string: "https://huggingface.co/mlx-community/gemma-3-1b-it-8bit/blob/main/model.safetensors")!,
            fileExtension: "gguf",
            tokenizerURL: URL(string: "https://huggingface.co/mlx-community/gemma-3-1b-it-8bit/blob/main/tokenizer.json")!,
            size: "1.4 GB",
            promptFormat: .gemma
        ),
        MLXModelDownloadInfo(
            name: "mlx-mistral-7b",
            displayName: "Mistral 7B (MLX)",
            url: URL(string: "https://huggingface.co/mlx-community/mistral-7b-v0.1-mlx/resolve/main/mistral-7b-v0.1-mlx.safetensors")!,
            fileExtension: "gguf",
            tokenizerURL: URL(string: "https://huggingface.co/mlx-community/mistral-7b-v0.1-mlx/resolve/main/tokenizer.json")!,
            size: "3.9 GB",
            promptFormat: .mistral
        )
    ]
}
