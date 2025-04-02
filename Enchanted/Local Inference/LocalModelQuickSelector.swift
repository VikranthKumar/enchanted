////
////  LocalModelQuickSelector.swift
////  Enchanted
////
////  Created by Vikranth Kumar on 4/1/25.
////
////
//// LocalModelQuickSelector.swift
//// A quick selector for local models to be used in chat view
////
//
//import SwiftUI
//
//#if os(macOS)
//import AppKit
//#endif
//
//struct LocalModelQuickSelector: View {
//    @State private var localModels: [LanguageModel] = []
//    @AppStorage("selectedLocalModel") private var selectedLocalModel: String = ""
//    @State private var showLocalModelsSheet = false
//    var onSelectModel: (String) -> Void
//    
//    func loadLocalModels() {
//        Task {
//            if let models = try? await LocalModelService.shared.getModels() {
//                DispatchQueue.main.async {
//                    self.localModels = models
//                }
//            }
//        }
//    }
//    
//    var body: some View {
//        Menu {
//            if localModels.isEmpty {
//                Text("No local models available")
//                    .foregroundColor(.secondary)
//                
//                Divider()
//                
//                Button(action: {
//                    showLocalModelsSheet = true
//                }) {
//                    Label("Download Models...", systemImage: "square.and.arrow.down")
//                }
//            } else {
//                ForEach(localModels, id: \.self) { model in
//                    Button(action: {
//                        selectedLocalModel = model.name
//                        onSelectModel(model.name)
//                    }) {
//                        HStack {
//                            Text(model.name)
//                            
//                            Spacer()
//                            
//                            if selectedLocalModel == model.name {
//                                Image(systemName: "checkmark")
//                            }
//                        }
//                    }
//                }
//            }
//        } label: {
//            HStack {
//                Image(systemName: "cpu")
//                Text(selectedLocalModel.isEmpty ? "Select Local Model" : selectedLocalModel)
//                Image(systemName: "chevron.down")
//                    .font(.caption)
//            }
//            .padding(.horizontal, 10)
//            .padding(.vertical, 5)
//            .background(Color.gray.opacity(0.1))
//            .cornerRadius(8)
//        }
//        .sheet(isPresented: $showLocalModelsSheet) {
//            LocalModelsView()
//                .modifier(SheetSizeModifier())
//        }
//        .onAppear {
//            loadLocalModels()
//        }
//        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
//            loadLocalModels()
//        }
//    }
//}
//
//// For iOS
//#if os(iOS)
//struct LocalModelQuickSelector_iOS: View {
//    @State private var localModels: [LanguageModel] = []
//    @AppStorage("selectedLocalModel") private var selectedLocalModel: String = ""
//    @State private var showingActionSheet = false
//    @State private var showLocalModelsSheet = false
//    var onSelectModel: (String) -> Void
//    
//    func loadLocalModels() {
//        Task {
//            if let models = try? await LocalModelService.shared.getModels() {
//                DispatchQueue.main.async {
//                    self.localModels = models
//                }
//            }
//        }
//    }
//    
//    var body: some View {
//        Button(action: {
//            if localModels.isEmpty {
//                showLocalModelsSheet = true
//            } else {
//                showingActionSheet = true
//            }
//        }) {
//            HStack {
//                Image(systemName: "cpu")
//                Text(selectedLocalModel.isEmpty ? "Select Local Model" : selectedLocalModel)
//                    .font(.body)
//                Image(systemName: "chevron.down")
//                    .font(.body)
//            }
//            .foregroundColor(.black)
//            .padding(.horizontal, 10)
//            .padding(.vertical, 5)
//            .background(Color.gray.opacity(0.1))
//            .cornerRadius(8)
//        }
//        .actionSheet(isPresented: $showingActionSheet) {
//            ActionSheet(
//                title: Text("Select Local Model"),
//                buttons: localModels.map { model in
//                        .default(Text(model.name + (selectedLocalModel == model.name ? " ✓" : ""))) {
//                            selectedLocalModel = model.name
//                            onSelectModel(model.name)
//                        }
//                } + [
//                    .default(Text("Download More Models...")) {
//                        showLocalModelsSheet = true
//                    },
//                    .cancel()
//                ]
//            )
//        }
//        .sheet(isPresented: $showLocalModelsSheet) {
//            LocalModelsView()
//        }
//        .onAppear {
//            loadLocalModels()
//        }
//        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
//            loadLocalModels()
//        }
//    }
//}
//#endif
//
//#if os(visionOS)
//// For visionOS, we'll use the same component as macOS but with some adjustments
//typealias LocalModelQuickSelector_VisionOS = LocalModelQuickSelector
//#endif
