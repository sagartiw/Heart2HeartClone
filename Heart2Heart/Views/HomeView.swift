// Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    private var firestoreManager = FirestoreManager()
    
    // User scores
    @State private var userScore: Double = 0
    @State private var userAverage: Double = 0
    @State private var userMaxScore: Double = 0
    @State private var userMinScore: Double = 0
    
    // Partner scores
    @State private var partnerScore: Double = 0
    @State private var partnerAverage: Double = 0
    @State private var partnerMaxScore: Double = 0
    @State private var partnerMinScore: Double = 0
    @State private var partnerName: String = "Partner"
    
    @State private var isLoading = true
    @State private var partnerId: String?
    @State private var showPartnerInvitation = false
        
        var body: some View {
            ZStack {
                Color(red: 0.141, green: 0.141, blue: 0.141)
                                .ignoresSafeArea()
                HStack(spacing: 40) {
                    // User Battery
                    VStack {
                        BatteryView(
                            value: userScore,
                            minValue: userMinScore,
                            maxValue: userMaxScore,
                            isInverted: false,
                            averageValue: userAverage,
                            isEmpty: false
                        )
                        .frame(height: 400)
                        
                        ZStack {
                            Text(authManager.user?.displayName ?? "User")
                        }
                        .frame(height: 30) // Same fixed height as partner side
                    }
                    
                    // Partner Battery or Empty Battery with Invite Button
                    VStack {
                        BatteryView(
                            value: partnerId != nil ? partnerScore : 0,
                            minValue: partnerId != nil ? partnerMinScore : 0,
                            maxValue: partnerId != nil ? partnerMaxScore : 100,
                            isInverted: false,
                            averageValue: partnerId != nil ? partnerAverage : 0,
                            isEmpty: partnerId == nil
                        )
                        .frame(height: 400)
                        .opacity(partnerId != nil ? 1 : 0.5)
                        
                        ZStack {
                            if partnerId != nil {
                                Text(partnerName)
                            } else {
                                Button("Invite Partner") {
                                    showPartnerInvitation = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(height: 30)
                    }
                }
                .padding(40)
                .foregroundColor(Color(red:0.894,green: 0.949, blue: 0.839))
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .sheet(isPresented: $showPartnerInvitation) {
                PartnerInvitationView(isPresented: $showPartnerInvitation)
            }
            .onAppear {
                Task {
                    await loadPartnerInfo()
                    await loadScores()
                }
            }
        }

        private func loadPartnerInfo() async {
            guard let currentUserId = authManager.user?.uid else {
                print("No user logged in")
                return
            }
            
            do {
                let (partnerId, _) = try await firestoreManager.getUserData(userId: currentUserId)
                
                if let partnerId = partnerId {
                    let (_, partnerName) = try await firestoreManager.getUserData(userId: partnerId)
                    
                    await MainActor.run {
                        self.partnerId = partnerId
                        self.partnerName = partnerName ?? "Partner"
                    }
                } else {
                    await MainActor.run {
                        self.partnerId = nil
                        self.partnerName = "Partner"
                    }
                }
            } catch {
                print("Error loading partner info: \(error)")
                await MainActor.run {
                    self.partnerId = nil
                    self.partnerName = "Partner"
                }
            }
        }
        
    func loadScores() async {
        guard let currentUserId = authManager.user?.uid else {
            print("No user logged in")
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        let today = Date()
        let days = settingsManager.settings.averagingPeriodDays
        
        // Load user scores
        let userResults = await loadUserScores(userId: currentUserId, days: days, today: today)
        
        // Load partner scores if partner exists
        let partnerResults: (latest: Double?, average: Double, max: Double, min: Double)
        if let partnerId = partnerId {
            partnerResults = await loadUserScores(userId: partnerId, days: days, today: today)
        } else {
            partnerResults = (latest: nil, average: 0, max: 0, min: 0)
        }
        
        await MainActor.run {
            // Update user scores
            userScore = userResults.latest ?? 0
            userAverage = userResults.average
            userMaxScore = userResults.max
            userMinScore = userResults.min
            
            // Update partner scores
            if partnerId != nil {
                partnerScore = partnerResults.latest ?? 0
                partnerAverage = partnerResults.average
                partnerMaxScore = partnerResults.max
                partnerMinScore = partnerResults.min
            } else {
                partnerScore = 0
                partnerAverage = 0
                partnerMaxScore = 100
                partnerMinScore = 0
            }
            
            isLoading = false
        }
    }
        private func loadUserScores(userId: String, days: Int, today: Date) async -> (latest: Double?, average: Double, max: Double, min: Double) {
            let calendar = Calendar.current
            var scores: [Double] = []
            var latest: Double?
            
            for i in 0..<days {
                let date = calendar.date(byAdding: .day, value: -days + i, to: today)!
                
                do {
                    if let score = try await firestoreManager.getComputedData(
                        userId: userId,
                        metric: .bandwidth,
                        date: date
                    ) {
                        scores.append(score)
                        latest = score
                    }
                } catch {
                    print("Error loading scores for date \(date): \(error)")
                }
            }
            
            guard !scores.isEmpty else {
                return (nil, 0, 0, 0)
            }
            
            let average = scores.reduce(0, +) / Double(scores.count)
            let maxScore = scores.max() ?? 0
            let minScore = scores.min() ?? 0
            
            return (latest, average, maxScore, minScore)
        }
    }

