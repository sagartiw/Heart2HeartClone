// Views/SettingsView.swift
import SwiftUI
import Combine
import Foundation

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var healthDataProcessor: HealthDataProcessor
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    @EnvironmentObject var authManager: AuthenticationManager
    
    static let displayNames: [String: String] = [
        "sleep": "Sleep",
        "exercise": "Exercise",
        "heartRate": "Heart Rate",
        "currentDay": "Current Day",
        "yesterday": "Yesterday",
        "twoDaysAgo": "Two Days Ago",
        "minutes": "Active Minutes",
        "calories": "Calories Burned",
        "steps": "Step Count",
        "elevated": "Elevated Heart Rate",
        "variability": "Heart Rate Variability",
        "resting": "Resting Heart Rate"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Data Collection")) {
                    Stepper(
                        value: $settingsManager.settings.averagingPeriodDays,
                        in: 30...90,
                        step: 30
                    ) {
                        HStack {
                            Text("Averaging Period")
                            Spacer()
                            Text("\(settingsManager.settings.averagingPeriodDays) days")
                        }
                    }
                }
                
                weightSection("Recent Days", weights: $settingsManager.settings.recentDaysWeights)
                
                Section(header: Text("Categories")) {
                    categoryToggles
                    categoryWeights
                }
                
                if settingsManager.settings.isExerciseEnabled {
                    weightSection("Exercise", weights: $settingsManager.settings.exerciseWeights)
                }
                
                if settingsManager.settings.isHeartRateEnabled {
                    weightSection("Heart Rate", weights: $settingsManager.settings.heartRateWeights)
                    heartRateThreshold
                }
                
                saveButton
            }
            .navigationTitle("Settings")
            .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sign Out") {
                            try? authManager.signOut()
                        }
                        .foregroundColor(.red)
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Reset") {
                            settingsManager.resetToDefaults()
                        }
                    }
                }
            .alert(isSuccess ? "Success" : "Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private var categoryToggles: some View {
        Group {
            ForEach(["Sleep", "Exercise", "Heart Rate"], id: \.self) { category in
                Toggle(category, isOn: binding(for: category))
                    .tint(Color(red: 0.794, green: 0.849, blue: 0.739))
            }
        }
    }
    
    private func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: {
                switch category {
                case "Sleep": return settingsManager.settings.isSleepEnabled
                case "Exercise": return settingsManager.settings.isExerciseEnabled
                case "Heart Rate": return settingsManager.settings.isHeartRateEnabled
                default: return false
                }
            },
            set: { newValue in
                switch category {
                case "Sleep": settingsManager.settings.isSleepEnabled = newValue
                case "Exercise": settingsManager.settings.isExerciseEnabled = newValue
                case "Heart Rate": settingsManager.settings.isHeartRateEnabled = newValue
                default: break
                }
                settingsManager.handleCategoryToggle()
            }
        )
    }
    
    private var categoryWeights: some View {
        ForEach(Array(settingsManager.settings.mainWeights.keys), id: \.self) { key in
            WeightSlider(
                title: SettingsView.displayNames[key] ?? key.capitalized,
                value: .init(
                    get: { settingsManager.settings.mainWeights[key] ?? 0 },
                    set: { settingsManager.settings.mainWeights[key] = $0 }
                )
            )
        }
    }
    
    private var heartRateThreshold: some View {
        Section(header: Text("Threshold")) {
            WeightSlider(
                title: "Elevated HR Threshold",
                value: $settingsManager.settings.elevatedHeartRateThreshold,
                range: 60...90,
                unit: "% of max HR"
            )
        }
    }
    
    private func weightSection(_ title: String, weights: Binding<[String: Double]>) -> some View {
        Section(header: Text("\(title) (percentage within category)")) {
            ForEach(Array(weights.wrappedValue.keys), id: \.self) { key in
                WeightSlider(
                    title: SettingsView.displayNames[key] ?? key.capitalized,
                    value: .init(
                        get: { weights.wrappedValue[key] ?? 0 },
                        set: { weights.wrappedValue[key] = $0 }
                    )
                )
            }
        }
    }
    
    private var saveButton: some View {
        Button("Save Settings") {
            let (isValid, message) = settingsManager.saveSettings()
            
            isSuccess = isValid
            alertMessage = message
            showAlert = true
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct WeightSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var unit: String = "%"
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(displayText)
                .frame(width: 60)
            Stepper("", value: $value, in: range, step: 5) { _ in
                value = round(value)
            }
            .labelsHidden()
        }
    }
    
    private var displayText: String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))\(unit)"
        } else {
            return String(format: "%.1f%@", value, unit)
        }
    }
}



#Preview {
    SettingsView()
}

