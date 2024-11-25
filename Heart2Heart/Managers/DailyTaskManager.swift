//DailyTaskManager.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import FirebaseFunctions


class DailyTaskManager: ObservableObject {
    private let healthDataProcessor: HealthDataProcessor
    private let firestoreManager: FirestoreManager
    private let settingsManager: SettingsManager
    
    @Published private(set) var isProcessing = false
    @Published private(set) var lastProcessedDate: Date?
    @Published private(set) var lastError: String?
    
    private var lastEarlyWindowAlert: Date?
    private var lastLateWindowAlert: Date?
    
    
    
    init(healthDataProcessor: HealthDataProcessor, settingsManager: SettingsManager) {
        self.healthDataProcessor = healthDataProcessor
        self.firestoreManager = FirestoreManager()
        self.settingsManager = settingsManager
    }
    
    
    private enum AuthError: Error {
        case userNotAuthenticated
    }
    
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private var processingTask: Task<Void, Error>?
    
    func handlePushNotification(userInfo: [AnyHashable: Any]) {
        processingTask?.cancel()
        
        processingTask = Task { @MainActor in
            do {
                isProcessing = true
                
                // Ensure we have enough background time
                let backgroundTask = UIApplication.shared.beginBackgroundTask {
                    self.processingTask?.cancel()
                }
                
                defer {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
                
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw AuthError.userNotAuthenticated
                }
                
                let date = Date()
                let score = try await healthDataProcessor.calculateBandwidthScore(for: date)
                
                try await firestoreManager.storeComputedData(
                    userId: userId,
                    metric: .bandwidth,
                    date: date,
                    value: score
                )
                
                try await analyzeScoreIfNeeded(userId: userId, currentScore: score, date: date)
                
                lastProcessedDate = date
                lastError = nil
            } catch {
                lastError = "Failed to process daily task: \(error.localizedDescription)"
            }
            
            isProcessing = false
        }
    }
    
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    
    private func isWithinTimeWindow() -> (inWindow: Bool, windowType: TimeWindow?) {
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let currentTime = hour * 60 + minute
            
            let earlyWindowStart = 16 * 60  // 4:00 PM
            let earlyWindowEnd = 17 * 60    // 5:00 PM
            let lateWindowStart = 18 * 60   // 6:00 PM
            let lateWindowEnd = 19 * 60     // 7:00 PM
            
            if currentTime >= earlyWindowStart && currentTime <= earlyWindowEnd {
                return (true, .early)
            } else if currentTime >= lateWindowStart && currentTime <= lateWindowEnd {
                return (true, .late)
            }
            return (false, nil)
        }
        
        private enum TimeWindow {
            case early
            case late
        }
        
        private func canSendAlert(for window: TimeWindow) -> Bool {
            let calendar = Calendar.current
            let now = Date()
            
            switch window {
            case .early:
                if let lastAlert = lastEarlyWindowAlert,
                   calendar.isDate(lastAlert, inSameDayAs: now) {
                    return false
                }
            case .late:
                if let lastAlert = lastLateWindowAlert,
                   calendar.isDate(lastAlert, inSameDayAs: now) {
                    return false
                }
            }
            return true
        }
    
    private func analyzeScoreIfNeeded(userId: String, currentScore: Double, date: Date) async throws {
        let windowStatus = isWithinTimeWindow()
                guard windowStatus.inWindow,
                      let windowType = windowStatus.windowType,
                      canSendAlert(for: windowType) else { return }
        
        // Fetch historical scores
        let calendar = Calendar.current
        let endDate = date
        let startDate = calendar.date(byAdding: .day,
                                      value: -settingsManager.settings.averagingPeriodDays,
                                      to: endDate) ?? endDate
        
        var historicalScores: [Double] = []
        var currentDate = startDate
        while currentDate <= endDate {
            if let score = try await firestoreManager.getComputedData(
                userId: userId,
                metric: .bandwidth,
                date: currentDate
            ) {
                historicalScores.append(score)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // Calculate percentile of current score
        let percentile = calculatePercentile(currentScore: currentScore,
                                             historicalScores: historicalScores)
        
        // If score is below threshold, trigger action
        let threshold = 0.2
                if percentile <= threshold {
                    try await handleLowScore(userId: userId, score: currentScore, percentile: percentile)
                    
                    // Update the last alert time for the current window
                    switch windowType {
                    case .early:
                        lastEarlyWindowAlert = date
                    case .late:
                        lastLateWindowAlert = date
                    }
                }
    }
    
    private func calculatePercentile(currentScore: Double, historicalScores: [Double]) -> Double {
        let sortedScores = historicalScores.sorted()
        let position = sortedScores.firstIndex { $0 >= currentScore } ?? sortedScores.count
        return Double(position) / Double(sortedScores.count)
    }
    
    private func handleLowScore(userId: String, score: Double, percentile: Double) async throws {
        // Get partner data
        let (partnerId, partnerName) = try await firestoreManager.getPartnerData(userId: userId)
        
        guard let partnerId = partnerId else {
            print("No partner found for user")
            return
        }
        
        // Get partner's FCM token from Firestore
        let partnerDoc = try await Firestore.firestore()
            .collection("users")
            .document(partnerId)
            .getDocument()
        
        guard let partnerToken = partnerDoc.data()?["fcmToken"] as? String else {
            print("No FCM token found for partner")
            return
        }
        
        // Create the notification message
        let message: [String: Any] = [
            "notification": [
                "title": "Partner Alert",
                "body": "Your partner might need some support today, there bandwidth is low."
            ],
            "data": [
                "type": "partnerAlert",
                "score": String(score),
                "percentile": String(percentile)
            ],
            "token": partnerToken
        ]
        
        // Send the notification using a Cloud Function
        let functions = Functions.functions()
        try await functions.httpsCallable("sendPartnerNotification").call(message)
    }}
