//
//  ModelSelector.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI

struct ModelSelectorView: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: @MainActor (_ model: LanguageModelSD?) -> ()
    var showChevron = true
    
    var body: some View {
        Menu {
            ForEach(modelsList, id: \.self) { model in
                Button(action: {
                    withAnimation(.easeOut) {
                        onSelectModel(model)
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.body)
                                .tag(model.name)
                            
                            if model.modelProvider == .local {
                                Text("Local inference")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if model.modelProvider == .local {
                            HStack(spacing: 2) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                
                                Text("Local")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .center) {
                if let selectedModel = selectedModel {
                    HStack(alignment: .bottom, spacing: 5) {
                        
#if os(macOS) || os(visionOS)
                        Text(selectedModel.name)
                            .font(.body)
                        
                        if selectedModel.modelProvider == .local {
                            HStack(spacing: 2) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                
                                Text("Local")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                        }
#elseif os(iOS)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(selectedModel.prettyName)
                                    .font(.body)
                                    .foregroundColor(Color.labelCustom)
                                
                                if selectedModel.modelProvider == .local {
                                    HStack(spacing: 2) {
                                        Image(systemName: "cpu")
                                            .font(.caption)
                                        
                                        Text("Local")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(Capsule())
                                }
                            }
                            
                            Text(selectedModel.prettyVersion)
                                .font(.subheadline)
                                .foregroundColor(Color.gray3Custom)
                        }
#endif
                    }
                }
                
                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10)
                    .foregroundColor(Color(.label))
                    .showIf(showChevron)
            }
        }
    }
}

#Preview {
    ModelSelectorView(
        modelsList: LanguageModelSD.sample,
        selectedModel: LanguageModelSD.sample[0], 
        onSelectModel: {_ in},
        showChevron: false
    )
}
