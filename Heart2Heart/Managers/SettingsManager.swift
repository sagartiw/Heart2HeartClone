// Managers/SettingsManager.swift
import SwiftUI

class SettingsManager: ObservableObject {
    @Published var settings: Settings
    private var savedSettings: Settings // Keep track of last saved settings
    
    
    struct Settings: Codable, Equatable {  // Add Equatable conformance
            var isSleepEnabled = false
            var isExerciseEnabled = true
            var isHeartRateEnabled = true
            var mainWeights: [String: Double]
            var recentDaysWeights: [String: Double]
            var exerciseWeights: [String: Double]
            var heartRateWeights: [String: Double]
            var elevatedHeartRateThreshold = 75.0
            var averagingPeriodDays: Int = 30
            
            // Implement custom Equatable conformance if needed
            static func == (lhs: Settings, rhs: Settings) -> Bool {
                return lhs.isSleepEnabled == rhs.isSleepEnabled &&
                       lhs.isExerciseEnabled == rhs.isExerciseEnabled &&
                       lhs.isHeartRateEnabled == rhs.isHeartRateEnabled &&
                       lhs.mainWeights == rhs.mainWeights &&
                       lhs.recentDaysWeights == rhs.recentDaysWeights &&
                       lhs.exerciseWeights == rhs.exerciseWeights &&
                       lhs.heartRateWeights == rhs.heartRateWeights &&
                       lhs.elevatedHeartRateThreshold == rhs.elevatedHeartRateThreshold
            }
        
        static let `default` = Settings(
            mainWeights: ["sleep": 50, "exercise": 30, "heartRate": 20],
            recentDaysWeights: ["currentDay": 70, "yesterday": 20, "twoDaysAgo": 10],
            exerciseWeights: ["minutes": 50, "calories": 30, "steps": 20],
            heartRateWeights: ["elevated": 40, "variability": 35, "resting": 25],
            averagingPeriodDays: 30
        )
    }
    
    init() {
            if let data = UserDefaults.standard.data(forKey: "settings"),
               let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
                self.settings = decoded
                self.savedSettings = decoded
            } else {
                self.settings = .default
                self.savedSettings = .default
            }
        }
        
    func saveSettings() -> (Bool, String) {
            let (isValid, message) = validateWeights()
            
            if isValid {
                if let encoded = try? JSONEncoder().encode(settings) {
                    UserDefaults.standard.set(encoded, forKey: "settings")
                    savedSettings = settings
                    objectWillChange.send()
                }
            } else {
                settings = savedSettings
                objectWillChange.send()
            }
            
            return (isValid, message)
        }
    
        
        func resetToDefaults() {
            settings = .default
            saveSettings() // Save default settings
            redistributeMainWeights()
        }
        
    
    func handleCategoryToggle() {
        redistributeMainWeights()
        
        if !settings.isSleepEnabled {
            settings.mainWeights.removeValue(forKey: "sleep")
        }
        
        if !settings.isExerciseEnabled {
            settings.mainWeights.removeValue(forKey: "exercise")
            // Reset exercise weights to 0 while maintaining structure
            settings.exerciseWeights = ["minutes": 0, "calories": 0, "steps": 0]
        } else {
            // When enabled, use default proportions that sum to 100
            settings.exerciseWeights = Settings.default.exerciseWeights
        }
        
        if !settings.isHeartRateEnabled {
            settings.mainWeights.removeValue(forKey: "heartRate")
            // Reset heart rate weights to 0 while maintaining structure
            settings.heartRateWeights = ["elevated": 0, "variability": 0, "resting": 0]
            settings.elevatedHeartRateThreshold = Settings.default.elevatedHeartRateThreshold
        } else {
            // When enabled, use default proportions that sum to 100
            settings.heartRateWeights = Settings.default.heartRateWeights
        }
    }
    
    func redistributeMainWeights() {
        let enabledCategories = [
            ("sleep", settings.isSleepEnabled),
            ("exercise", settings.isExerciseEnabled),
            ("heartRate", settings.isHeartRateEnabled)
        ].filter { $0.1 }
        
        let count = Double(enabledCategories.count)
        guard count > 0 else { return }
        
        var weights: [String: Double] = [:]
        switch count {
        case 1:
            weights[enabledCategories[0].0] = 100
        case 2:
            weights[enabledCategories[0].0] = 60
            weights[enabledCategories[1].0] = 40
        case 3:
            weights["sleep"] = 50
            weights["exercise"] = 30
            weights["heartRate"] = 20
        default:
            break
        }
        
        settings.mainWeights = weights
    }
    
    func validateWeights() -> (Bool, String) {
        let mainSum = settings.mainWeights.values.reduce(0, +)
        let recentSum = settings.recentDaysWeights.values.reduce(0, +)
        let exerciseSum = settings.exerciseWeights.values.reduce(0, +)
        let heartRateSum = settings.heartRateWeights.values.reduce(0, +)
        
        if abs(mainSum - 100) > 0.1 {
            return (false, "Main category weights must sum to 100%")
        }
        
        if abs(recentSum - 100) > 0.1 {
            return (false, "Recent days weights must sum to 100%")
        }
        
        if settings.isExerciseEnabled && abs(exerciseSum - 100) > 0.1 {
            return (false, "Exercise weights must sum to 100%")
        }
        
        if settings.isHeartRateEnabled && abs(heartRateSum - 100) > 0.1 {
            return (false, "Heart rate weights must sum to 100%")
        }
        
        return (true, "Settings saved successfully")
    }
}
