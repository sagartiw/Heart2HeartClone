//AlertManager.swift

import Foundation
import FirebaseFirestore
import Combine

struct Alert: Identifiable {
    let id: String
    let type: AlertType
    let fromUserId: String
    let fromUserName: String
    let score: Double
    let percentile: Double
    let timestamp: Date
    let status: AlertStatus
    
    enum AlertType: String {
        case lowBandwidthAlert
        // Add other alert types as needed
    }
    
    enum AlertStatus: String {
        case unread
        case read
    }
    
    var message: String {
        "Today, \(fromUserName)'s Bandwidth score is in the lowest 20% of historical data."
    }
}

class AlertManager: ObservableObject {
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    @Published var alerts: [Alert] = []
    
    func startListening(forUserId userId: String) {
        listener = db.collection("users")
            .document(userId)
            .collection("alerts")
            .whereField("status", isEqualTo: "unread")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let newAlerts = documents.compactMap { document -> Alert? in
                    guard
                        let type = document.data()["type"] as? String,
                        let fromUserId = document.data()["fromUserId"] as? String,
                        let fromUserName = document.data()["fromUserName"] as? String,
                        let score = document.data()["score"] as? Double,
                        let percentile = document.data()["percentile"] as? Double,
                        let timestamp = document.data()["timestamp"] as? Timestamp,
                        let status = document.data()["status"] as? String
                    else { return nil }
                    
                    return Alert(
                        id: document.documentID,
                        type: Alert.AlertType(rawValue: type) ?? .lowBandwidthAlert,
                        fromUserId: fromUserId,
                        fromUserName: fromUserName,
                        score: score,
                        percentile: percentile,
                        timestamp: timestamp.dateValue(),
                        status: Alert.AlertStatus(rawValue: status) ?? .unread
                    )
                }
                
                DispatchQueue.main.async {
                    self?.alerts = newAlerts
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
