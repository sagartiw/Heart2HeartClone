//Heart2Heart.swift
import SwiftUI
import Firebase

@main
struct Heart2Heart: App {
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var healthDataProcessor: HealthDataProcessor
    @StateObject private var dailyTaskManager: DailyTaskManager
    
    init() {
        FirebaseApp.configure()
        
        let auth = AuthenticationManager()
        let settings = SettingsManager()
        
        _authManager = StateObject(wrappedValue: auth)
        _settingsManager = StateObject(wrappedValue: settings)
        
        let health = HealthDataProcessor(
            settingsManager: settings,
            authManager: auth
        )
        _healthDataProcessor = StateObject(wrappedValue: health)
        
        // Initialize DailyTaskManager with healthDataProcessor
        let dailyTask = DailyTaskManager(healthDataProcessor: health)
        _dailyTaskManager = StateObject(wrappedValue: dailyTask)
        
        configureUIAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(settingsManager)
                .environmentObject(healthDataProcessor)
                .environmentObject(dailyTaskManager)
                .task {
                    await initializeHealthKit()
                }
                .onAppear {
                    dailyTaskManager.startListening()
                }
        }
    }
    
    private func initializeHealthKit() async {
        do {
            try await healthDataProcessor.initialize()
            print("HealthKit initialized successfully")
        } catch {
            print("HealthKit initialization failed: \(error.localizedDescription)")
        }
    }
    
    private func configureUIAppearance() {
        let kulimParkSemiBold = "KulimPark-SemiBold"
        
        UILabel.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UITextField.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UITextView.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: kulimParkSemiBold, size: 34)!
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: kulimParkSemiBold, size: 17)!
        ]
    }
}