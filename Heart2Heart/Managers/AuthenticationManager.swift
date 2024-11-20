import Firebase
import FirebaseAuth

class AuthenticationManager: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isOnboarding = false
    private let db = Firestore.firestore()
    
    init() {
        validateCurrentUser()
        
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.handleAuthStateChange(user)
            }
        }
    }
    
    private func handleAuthStateChange(_ user: User?) {
        self.user = user
        self.isAuthenticated = user != nil
        
        if let user = user {
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding_\(user.uid)")
            self.isOnboarding = !hasCompletedOnboarding
        }
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
        
        // Get current timezone identifier
        let timezone = TimeZone.current.identifier
        
        try await db.collection("users").document(result.user.uid).setData([
            "email": email,
            "name": name,
            "createdAt": FieldValue.serverTimestamp()
        ])
        
        await MainActor.run {
            self.user = result.user
            self.isAuthenticated = true
            self.isOnboarding = true
        }
    }
    
    func completeOnboarding() {
        guard let userId = user?.uid else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_\(userId)")
        self.isOnboarding = false
    }

    @MainActor
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        DispatchQueue.main.async {
            self.user = nil
            self.isAuthenticated = false
        }
    }
    
    private func validateCurrentUser() {
        if let currentUser = Auth.auth().currentUser {
            currentUser.reload { [weak self] error in
                if let error = error {
                    print("Error reloading user: \(error.localizedDescription)")
                    try? self?.signOut()
                }
            }
        }
    }
    
    // MARK: - Partner Pairing Functions
    
    func generateInvitationCode() async throws -> String {
        guard let userId = user?.uid else {
            throw AuthError.noUserFound
        }
        
        let code = String(format: "%06d", Int.random(in: 0...999999))
        
        // Check if code exists
        let snapshot = try await db.collection("users")
            .whereField("invitationCode", isEqualTo: code)
            .getDocuments()
        
        if !snapshot.documents.isEmpty {
            return try await generateInvitationCode() // Try again with new code
        }
        
        // Save the unique code
        try await db.collection("users").document(userId).updateData([
            "invitationCode": code
        ])
        
        return code
    }
    
    func validateAndGetPartner(code: String) async throws -> (id: String, name: String) {
        guard let currentUserId = user?.uid else {
            throw AuthError.noUserFound
        }
        
        let snapshot = try await db.collection("users")
            .whereField("invitationCode", isEqualTo: code)
            .getDocuments()
        
        guard let partnerDoc = snapshot.documents.first,
              partnerDoc.documentID != currentUserId else {
            throw AuthError.invalidCode
        }
        
        let partnerName = partnerDoc.data()["name"] as? String ?? "Unknown"
        return (partnerDoc.documentID, partnerName)
    }
    
    func completePairing(withPartnerId partnerId: String) async throws {
        guard let currentUserId = user?.uid else {
            throw AuthError.noUserFound
        }
        
        let batch = db.batch()
        let currentUserRef = db.collection("users").document(currentUserId)
        let partnerRef = db.collection("users").document(partnerId)
        
        batch.updateData(["pairedWith": partnerId], forDocument: currentUserRef)
        batch.updateData([
            "pairedWith": currentUserId,
            "invitationCode": FieldValue.delete()
        ], forDocument: partnerRef)
        
        try await batch.commit()
        NotificationCenter.default.post(name: NSNotification.Name("PairingCompleted"), object: nil)
    }
    
    enum AuthError: LocalizedError {
        case noUserFound
        case invalidCode
        
        var errorDescription: String? {
            switch self {
            case .noUserFound:
                return "No user logged in"
            case .invalidCode:
                return "Invalid or expired code"
            }
        }
    }
}
