//Views/ComponentView

import SwiftUI

extension Double {
    func normalized(min: Double, max: Double) -> Double {
        guard max > min else { return 0 }
        let normalized = ((self - min) / (max - min)) * 100
        return Swift.min(Swift.max(normalized, 0), 100) // Clamp between 0 and 100
    }
}

struct ComponentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var healthDataProcessor: HealthDataProcessor

    private var firestoreManager = FirestoreManager()
    
    // User scores
    @State private var userCurrentScore: Double = 0
    @State private var userAverageScore: Double = 0
    @State private var userMaxScore: Double = 0
    @State private var userMinScore: Double = 0
    
    // Partner scores
    @State private var partnerCurrentScore: Double = 0
    @State private var partnerAverageScore: Double = 0
    @State private var partnerMaxScore: Double = 0
    @State private var partnerMinScore: Double = 0
    @State private var partnerId: String?
    
    @State private var isLoading = true
    @State private var selectedMetric: DisplayMetric = .bandwidthScore
    
    @State private var userName: String = ""
    @State private var partnerName: String = ""
        
    var body: some View {
        ZStack {
                Color(red: 0.141, green: 0.141, blue: 0.141)
                    .ignoresSafeArea()
            VStack(spacing: 5) {
                Menu {
                            ForEach([
                                DisplayMetric.healthMetric(.restingHeartRate),
                                DisplayMetric.healthMetric(.steps),
                                DisplayMetric.healthMetric(.activeEnergy),
                                DisplayMetric.healthMetric(.heartRateVariability),
                                DisplayMetric.healthMetric(.exerciseTime),
                                DisplayMetric.healthMetric(.elevatedHeartRateTime),
                                DisplayMetric.bandwidthScore
                            ], id: \.self) { metric in
                                Button {
                                    selectedMetric = metric
                                } label: {
                                    Text(metric.displayName)
                                        .font(.custom("KulimPark-SemiBold", size: 16))
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedMetric.displayName)
                                    .font(.custom("KulimPark-SemiBold", size: 16))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.down")
                                    .font(.custom("KulimPark-SemiBold", size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                
                // User section
                Text(userName)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading)
                
                HStack(spacing: 50) {
                    // Today Battery
                    VStack(spacing: 0) {
                        SmallBatteryView(
                            value: userCurrentScore,
                            minValue: userMinScore,
                            maxValue: userMaxScore,
                            isInverted: false,
                            isEmpty: false,
                            isGray: false
                        )
                        .frame(height: 250)  // Reduced height
                        .padding(.bottom, 2)  // Add small padding between battery and text
                        
                        Text("\(Int(userCurrentScore.normalized(min: userMinScore, max: userMaxScore)))%")
                            .font(.subheadline)
                        Text("Today")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    // Average Battery
                    VStack(spacing: 0) {
                        SmallBatteryView(
                            value: userAverageScore,
                            minValue: userMinScore,
                            maxValue: userMaxScore,
                            isInverted: false,
                            isEmpty: false,
                            isGray: true
                        )
                        .frame(height: 250)  // Reduced height
                        .padding(.bottom, 2)  // Add small padding between battery and text
                        
                        Text("\(Int(userAverageScore.normalized(min: userMinScore, max: userMaxScore)))%")
                            .font(.subheadline)
                        Text("Average")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // Partner section (similar changes)
                if partnerId != nil {
                    Text(partnerName)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading)
                    
                    HStack(spacing: 50) {
                        VStack(spacing: 0) {
                            SmallBatteryView(
                                value: partnerCurrentScore,
                                minValue: partnerMinScore,
                                maxValue: partnerMaxScore,
                                isInverted: false,
                                isEmpty: partnerId == nil,
                                isGray: false
                            )
                            .frame(height: 250)  // Reduced height
                            .padding(.bottom, 2)  // Add small padding between battery and text
                            
                            Text("\(Int(partnerCurrentScore.normalized(min: userMinScore, max: userMaxScore)))%")
                                .font(.subheadline)
                            Text("Today")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(spacing: 0) {
                            SmallBatteryView(
                                value: partnerAverageScore,
                                minValue: partnerMinScore,
                                maxValue: partnerMaxScore,
                                isInverted: false,
                                isEmpty: partnerId == nil,
                                isGray: true
                            )
                            .frame(height: 250)  // Reduced height
                            .padding(.bottom, 2)  // Add small padding between battery and text
                            
                            Text("\(Int(partnerAverageScore.normalized(min: userMinScore, max: userMaxScore)))%")
                                .font(.subheadline)
                            Text("Average")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .padding(20)
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .onAppear {
            Task {
                await loadPartnerInfo()
                await loadScores()
                await loadNames()
            }
        }
        .onChange(of: selectedMetric) { _ in
            Task {
                await loadScores()
            }
        }
    }

        private func loadNames() async {
            guard let currentUserId = authManager.user?.uid else { return }
            
            do {
                let (_, userName) = try await firestoreManager.getUserData(userId: currentUserId)
                await MainActor.run {
                    self.userName = userName ?? "User"
                }
                
                if let partnerId = partnerId {
                    let (_, partnerName) = try await firestoreManager.getUserData(userId: partnerId)
                    await MainActor.run {
                        self.partnerName = partnerName ?? "Partner"
                    }
                }
            } catch {
                print("Error loading names: \(error)")
            }
        }
    
    private func loadPartnerInfo() async {
        guard let currentUserId = authManager.user?.uid else {
            print("No user logged in")
            return
        }
        
        do {
            let (partnerId, _) = try await firestoreManager.getUserData(userId: currentUserId)
            await MainActor.run {
                self.partnerId = partnerId
            }
        } catch {
            print("Error loading partner info: \(error)")
            await MainActor.run {
                self.partnerId = nil
            }
        }
    }
    
    private func loadScores() async {
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
            partnerResults = (latest: nil, average: 0, max: 100, min: 0)
        }
        
        await MainActor.run {
            userCurrentScore = userResults.latest ?? 0
            userAverageScore = userResults.average
            userMaxScore = userResults.max
            userMinScore = userResults.min
            
            if partnerId != nil {
                partnerCurrentScore = partnerResults.latest ?? 0
                partnerAverageScore = partnerResults.average
                partnerMaxScore = partnerResults.max
                partnerMinScore = partnerResults.min
            } else {
                partnerCurrentScore = 0
                partnerAverageScore = 0
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
                let score: Double?
                switch selectedMetric {
                case .bandwidthScore:
                    score = try await firestoreManager.getComputedData(
                        userId: userId,
                        metric: .bandwidth,
                        date: date
                    )
                case .healthMetric(let metric):
                    score = try await healthDataProcessor.healthManager.getDailyMetric(metric, for: date)
                }
                
                if let score = score {
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
