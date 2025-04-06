//
//  AvailableModels.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/2/25.
//

import Foundation

// Predefined models
extension LocalModelService {
    static let availableModels = [
        ModelDownloadInfo(
            name: "llama-3-1b-instruct",
            displayName: "Llama 3.2 1B Instruct",
            url: URL(string: "https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q3_K_L.gguf")!,
            size: "733 MB",
            promptFormat: .llama3
        ),
        ModelDownloadInfo(
            name: "phi-2",
            displayName: "Phi-2",
            url: URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q2_K.gguf")!,
            size: "1.17 GB",
            promptFormat: .phi
        )
    ]
}
