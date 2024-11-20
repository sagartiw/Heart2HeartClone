//
//  View/ScoreView.swift
import SwiftUI

struct BandwidthScoreView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var healthDataProcessor: HealthDataProcessor
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack {
            if healthDataProcessor.isCalculating {
                ProgressView("Calculating...")
            } else if let error = healthDataProcessor.lastError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                Text("Bandwidth Score: \(healthDataProcessor.currentBandwidthScore, specifier: "%.1f")")
            }
            
            // Settings controls
            SettingsView()
        }
    }
}

// Preview provider
struct BandwidthScoreView_Previews: PreviewProvider {
    static var previews: some View {
        let settingsManager = SettingsManager()
        let authManager = AuthenticationManager()
        let healthDataProcessor = HealthDataProcessor(
            settingsManager: settingsManager,
            authManager: authManager
        )
        
        BandwidthScoreView()
            .environmentObject(settingsManager)
            .environmentObject(healthDataProcessor)
            .environmentObject(authManager)
    }
}
