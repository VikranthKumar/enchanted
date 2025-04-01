//
//  LocalModelError.swift
//  Enchanted
//
//  Created by Vikranth Kumar on 4/1/25.
//

import Foundation

//enum LocalModelError: Error, LocalizedError {
//    case modelNotFound
//    case modelNotInitialized
//    case failedToLoadModel
//    case incompatibleModel
//    case inferenceError(String)
//    
//    var errorDescription: String? {
//        switch self {
//            case .modelNotFound:
//                return "Model file not found on device"
//            case .modelNotInitialized:
//                return "Failed to initialize model"
//            case .failedToLoadModel:
//                return "Failed to load model"
//            case .incompatibleModel:
//                return "Model is not compatible with this device"
//            case .inferenceError(let details):
//                return "Inference error: \(details)"
//        }
//    }
//    
//    var failureReason: String? {
//        switch self {
//            case .modelNotFound:
//                return "The model file was not found in the local storage directory"
//            case .modelNotInitialized:
//                return "The model could not be initialized by SwiftLlama"
//            case .failedToLoadModel:
//                return "There was an error loading the model"
//            case .incompatibleModel:
//                return "This model format is not supported by the current version of SwiftLlama"
//            case .inferenceError(let details):
//                return details
//        }
//    }
//    
//    var recoverySuggestion: String? {
//        switch self {
//            case .modelNotFound:
//                return "Try downloading the model again"
//            case .modelNotInitialized:
//                return "Restart the app and try again"
//            case .failedToLoadModel:
//                return "Try downloading a different model or check your device's available memory"
//            case .incompatibleModel:
//                return "Try a different model or update the app"
//            case .inferenceError:
//                return "Try a different prompt or restart the app"
//        }
//    }
//}
