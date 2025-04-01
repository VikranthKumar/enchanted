//
//  AppStore.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import Foundation
import Combine
import SwiftUI

enum AppState {
    case chat
    case voice
}

@Observable
final class AppStore {
    static let shared = AppStore()
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var pingInterval: TimeInterval = 5
    @MainActor var isReachable: Bool = true
    @MainActor var notifications: [NotificationMessage] = []
    @MainActor var menuBarIcon: String? = nil
    @MainActor var isLocalInferenceEnabled: Bool = false

    var appState: AppState = .chat

    @MainActor
    init() {
        if let storedIntervalString = UserDefaults.standard.string(forKey: "pingInterval") {
            pingInterval = Double(storedIntervalString) ?? 5
            
            if pingInterval <= 0 {
                pingInterval = .infinity
            }
        }
        
        isLocalInferenceEnabled = UserDefaults.standard.bool(forKey: "useLocalInference")
        
        startCheckingReachability(interval: pingInterval)
        setupObservers()
    }
    
    deinit {
        stopCheckingReachability()
    }
    
    func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    @MainActor
    @objc private func userDefaultsDidChange() {
        isLocalInferenceEnabled = UserDefaults.standard.bool(forKey: "useLocalInference")
    }
    
    private func startCheckingReachability(interval: TimeInterval = 5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { [weak self] in
                let status = await self?.reachable() ?? false
                self?.updateReachable(status)
            }
        }
    }
    
    private func updateReachable(_ isReachable: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.isReachable = isReachable
            }
        }
    }

    private func stopCheckingReachability() {
        timer?.invalidate()
        timer = nil
    }

    private func reachable() async -> Bool {
        let status = await OllamaService.shared.reachable()
        return status
    }
    
    @MainActor func uiLog(message: String, status: NotificationMessage.Status) {
        notifications = [NotificationMessage(message: message, status: status)] + notifications.suffix(5)
    }
}
