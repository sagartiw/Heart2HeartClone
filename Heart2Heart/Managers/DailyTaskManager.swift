//Managers/DailyTaskManager.swift

import Foundation
import Firebase

class DailyTaskManager: ObservableObject {
    @Published var lastUpdate: Date?
    @EnvironmentObject var healthDataProcessor: HealthDataProcessor
    private var listener: ListenerRegistration?
    
    func startListening() {
        let db = Firestore.firestore()
        
        listener = db.collection("dailyTasks")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let document = snapshot?.documents.first,
                      let timestamp = document.data()["timestamp"] as? Timestamp else {
                    return
                }
                
                self.lastUpdate = timestamp.dateValue()
                Task {
                    await self.processDailyUpdate()
                }
            }
    }
    
    private func processDailyUpdate() async {
        guard let healthDataProcessor = healthDataProcessor else { return }
        
        do {
            try await healthDataProcessor.initialize()
            let today = Calendar.current.startOfDay(for: Date())
            _ = try await healthDataProcessor.calculateBandwidthScore(for: today)
        } catch {
            print("Error processing daily update: \(error)")
        }
    }
    
    deinit {
        listener?.remove()
    }
}
