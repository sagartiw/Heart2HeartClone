
//  Managers/BackgroundTaskManager.swift
import SwiftUI
import BackgroundTasks

class BackgroundTaskManager: ObservableObject {
    private let settingsManager: SettingsManager
    private let authManager: AuthenticationManager
    private let healthDataProcessor: HealthDataProcessor
    private let firestoreManager = FirestoreManager()
    private let taskIdentifier = "com.Heart2Heart.dailyCheck"
    
    init(settingsManager: SettingsManager,
         authManager: AuthenticationManager,
         healthDataProcessor: HealthDataProcessor) {
        self.settingsManager = settingsManager
        self.authManager = authManager
        self.healthDataProcessor = healthDataProcessor
        
        setupBackgroundTask()
    }
    
    private func setupBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleDailyTask(task: task as! BGAppRefreshTask)
        }
        scheduleDailyTask()
    }
    
    func scheduleDailyTask() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        let nextDate = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 14, minute: 37),
            matchingPolicy: .nextTime
        )
        
        request.earliestBeginDate = nextDate
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Task scheduled for: \(String(describing: nextDate))")
        } catch {
            print("Failed to schedule task: \(error)")
        }
    }
    
    private func handleDailyTask(task: BGAppRefreshTask) {
        print("FIRE")
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        
        Task {
            do {
                try await processHealthData()
                scheduleDailyTask()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    private func processHealthData() async throws {
        guard let userId = authManager.user?.uid else { return }
        
        try await healthDataProcessor.initialize()
        
        let today = Calendar.current.startOfDay(for: Date())
        let period = settingsManager.settings.averagingPeriodDays
        var scores: [Double] = []
        
        // Collect scores for the averaging period
        for dayOffset in 0..<period {
            let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today)!
            
            if let existingScore = try? await firestoreManager.getComputedData(
                userId: userId,
                metric: .bandwidth,
                date: date
            ) {
                scores.append(existingScore)
            } else {
                let score = try await healthDataProcessor.calculateBandwidthScore(for: date)
                scores.append(score)
                
                try await firestoreManager.storeComputedData(
                    userId: userId,
                    metric: .bandwidth,
                    date: date,
                    value: score
                )
            }
        }
        
        // Calculate percentile for today's score
        if let todayScore = scores.first {
            let sortedScores = scores.sorted()
            if let index = sortedScores.firstIndex(of: todayScore) {
                let percentile = Double(index + 1) / Double(scores.count) * 100
                if percentile <= 20 {
                    // Handle low score condition
                }
            }
        }
    }
}
