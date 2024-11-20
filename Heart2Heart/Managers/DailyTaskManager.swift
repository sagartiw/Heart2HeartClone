//DailyTaskManager.swift

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine


class DailyTaskManager: ObservableObject {
    private let db = Firestore.firestore()
    private let healthDataProcessor: HealthDataProcessor
    private let firestoreManager: FirestoreManager
    private let settingsManager: SettingsManager
    private var listener: ListenerRegistration?
    private var processingTask: Task<Void, Error>?
    
    @Published private(set) var isProcessing = false
    @Published private(set) var lastProcessedDate: Date?
    @Published private(set) var lastError: String?
    
    init(healthDataProcessor: HealthDataProcessor, settingsManager: SettingsManager) {
        self.healthDataProcessor = healthDataProcessor
        self.firestoreManager = FirestoreManager()
        self.settingsManager = settingsManager
    }
    
    func startListening() {
        stopListening()
        
        // Listen for tasks specific to the current user
        guard let userId = Auth.auth().currentUser?.uid else {
            lastError = "No authenticated user"
            return
        }
        
        listener = db.collection("dailyTasks")
            .whereField("userId", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.lastError = "Failed to listen for tasks: \(error.localizedDescription)"
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                // Process only the most recent task
                if let latestTask = documents.first {
                    self.processDailyTask(latestTask)
                }
            }
    }
    
    private func processDailyTask(_ document: QueryDocumentSnapshot) {
        guard !isProcessing else { return }
        
        processingTask = Task { @MainActor in
            do {
                isProcessing = true
                
                let taskData = document.data()
                let timestamp = taskData["timestamp"] as? Timestamp ?? Timestamp(date: Date())
                let taskDate = timestamp.dateValue()
                
                let score = try await healthDataProcessor.calculateBandwidthScore(for: taskDate)
                
                if let userId = taskData["userId"] as? String {
                    // Store the score
                    try await firestoreManager.storeComputedData(
                        userId: userId,
                        metric: .bandwidth,
                        date: taskDate,
                        value: score
                    )
                    
                    // Analyze the score
                    try await analyzeScoreIfNeeded(userId: userId,
                                                 currentScore: score,
                                                 date: taskDate)
                    
                    // Update task status
                    try await document.reference.updateData([
                        "status": "completed",
                        "score": score,
                        "processedAt": FieldValue.serverTimestamp()
                    ])
                    
                    lastProcessedDate = taskDate
                    lastError = nil
                } else {
                    throw FirestoreError.invalidUserId
                }
                
            } catch {
                lastError = "Failed to process daily task: \(error.localizedDescription)"
                try? await document.reference.updateData([
                    "status": "failed",
                    "error": error.localizedDescription,
                    "processedAt": FieldValue.serverTimestamp()
                ])
            }
            
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }
    
    private func isWithinTimeWindow() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentTime = hour * 60 + minute
        
        let earlyWindowStart = 16 * 60  // 4:00 PM
        let earlyWindowEnd = 17 * 60    // 5:00 PM
        let lateWindowStart = 18 * 60   // 6:00 PM
        let lateWindowEnd = 19 * 60     // 7:00 PM
        
        return (currentTime >= earlyWindowStart && currentTime <= earlyWindowEnd) ||
               (currentTime >= lateWindowStart && currentTime <= lateWindowEnd)
    }
    
    private func analyzeScoreIfNeeded(userId: String, currentScore: Double, date: Date) async throws {
        guard isWithinTimeWindow() else { return }
        
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
        if percentile < threshold {
            try await handleLowScore(userId: userId, score: currentScore, percentile: percentile)
        }
    }
    
    private func calculatePercentile(currentScore: Double, historicalScores: [Double]) -> Double {
        let sortedScores = historicalScores.sorted()
        let position = sortedScores.firstIndex { $0 >= currentScore } ?? sortedScores.count
        return Double(position) / Double(sortedScores.count)
    }
    
    // In DailyTaskManager.swift
    private func handleLowScore(userId: String, score: Double, percentile: Double) async throws {
        // Get the paired user's info
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let pairedUserId = userDoc.data()?["pairedWith"] as? String,
              let userName = userDoc.data()?["name"] as? String else {
            return
        }

        // Create alert data
        let alertData: [String: Any] = [
            "type": "lowBandwidthAlert",
            "fromUserId": userId,
            "fromUserName": userName,
            "score": score,
            "percentile": percentile,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "unread"
        ]

        // Store alert in Firestore
        try await db.collection("users")
            .document(pairedUserId)
            .collection("alerts")
            .addDocument(data: alertData)

        // Send notification
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = "Bandwidth Alert"
        notificationContent.body = "Today, \(userName)'s Bandwidth score is in the lowest 20% of historical data."
        notificationContent.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil
        )

        try await UNUserNotificationCenter.current().add(request)
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        processingTask?.cancel()
    }
        
    deinit {
        stopListening()
    }
}
