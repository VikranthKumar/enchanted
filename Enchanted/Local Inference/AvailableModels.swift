//
//  AvailableModels.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/2/25.
//

import Foundation

extension LocalModelService {
    
    // Predefined models
    static let availableModels = [
        ModelDownloadInfo(
            name: "gemma-3-1b-it",
            displayName: "Gemma 3 1B Instruct",
            url: URL(string: "https://huggingface.co/lmstudio-community/gemma-3-1b-it-GGUF/blob/main/gemma-3-1b-it-Q4_K_M.gguf")!,
            size: "806 MB",
            promptFormat: .gemma
        ),
        ModelDownloadInfo(
            name: "gemma-2-2b-it",
            displayName: "Gemma 2 2B Instruct",
            url: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/blob/main/gemma-2-2b-it-Q3_K_L.gguf")!,
            size: "1.55 GB",
            promptFormat: .gemma
        ),
        ModelDownloadInfo(
            name: "phi-2",
            displayName: "Phi-2",
            url: URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q2_K.gguf")!,
            size: "1.17 GB",
            promptFormat: .phi
        ),
        ModelDownloadInfo(
            name: "llama-3-1b-instruct",
            displayName: "Llama 3.2 1B Instruct",
            url: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q3_K_L.gguf")!,
            size: "733 MB",
            promptFormat: .llama3
        )
    ]
    
}
