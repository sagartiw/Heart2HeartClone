// Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var healthDataProcessor: HealthDataProcessor
    @AppStorage("hasShownInitialLoadAlert") private var hasShownInitialLoadAlert = false


    
    private let firestoreManager = FirestoreManager()
    
    @State private var userScores: [Double] = []
    @State private var partnerScores: [Double] = []
    @State private var partnerId: String?
    @State private var partnerName: String = "Partner"
    @State private var isLoading = true
    @State private var showPartnerInvitation = false
    @State private var showInitialLoadAlert = false
    @State private var needsHistoricalCalculation = false



    // Computed properties for statistics
    private var userStats: ScoreStats {
        ScoreStats(scores: userScores)
    }
    
    private var partnerStats: ScoreStats {
        ScoreStats(scores: partnerScores)
    }
    

    
    private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter
        }()
        
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.141, green: 0.141, blue: 0.141)
                    .ignoresSafeArea()
                
                VStack {
                    // Batteries HStack
                    HStack(spacing: 40) {
                        BatteryView(
                            value: userStats.latest,
                            minValue: userStats.min,
                            maxValue: userStats.max,
                            isInverted: false,
                            averageValue: userStats.average,
                            isEmpty: false
                        )
                        .frame(height: 400)
                        
                        BatteryView(
                            value: partnerId != nil ? partnerStats.latest : 0,
                            minValue: partnerId != nil ? partnerStats.min : 0,
                            maxValue: partnerId != nil ? partnerStats.max : 100,
                            isInverted: false,
                            averageValue: partnerId != nil ? partnerStats.average : 0,
                            isEmpty: partnerId == nil
                        )
                        .frame(height: 400)
                        .opacity(partnerId != nil ? 1 : 0.5)
                    }
                    
                    // Stats and Names HStack
                    HStack(spacing: 40) {
                        // User Stats and Name
                        VStack(spacing: 5) {
                            HStack(spacing: 20) {
                                VStack {
                                    Text("\(Int(userStats.latest.normalized(min: userStats.min, max: userStats.max)))%")
                                        .font(.subheadline)
                                    Text("Today")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                VStack {
                                    Text("\(Int(userStats.average.normalized(min: userStats.min, max: userStats.max)))%")
                                        .font(.subheadline)
                                    Text("Average")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                                .frame(height: 20)
                            
                            Text(authManager.user?.displayName ?? "User")
                        }
                        
                        // Partner Stats and Name
                        VStack(spacing: 5) {
                            if partnerId != nil {
                                HStack(spacing: 20) {
                                    VStack {
                                        Text("\(Int(partnerStats.latest.normalized(min: partnerStats.min, max: partnerStats.max)))%")
                                            .font(.subheadline)
                                        Text("Today")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    VStack {
                                        Text("\(Int(partnerStats.average.normalized(min: partnerStats.min, max: partnerStats.max)))%")
                                            .font(.subheadline)
                                        Text("Average")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            
                            Spacer()
                                .frame(height: 20)
                            
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
                        }
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
        .task {
            await loadData()
        }
            
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("Icon") 
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(dateFormatter.string(from: Date()))
                        .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(red:0.894, green: 0.949, blue: 0.839))
                    }
                }
            }
            .alert("Initial Setup", isPresented: $showInitialLoadAlert) {
                Button("OK") { }
            } message: {
                Text("Loading scores for the first time can take a minute or two. Please keep this tab open!")
            }
        }
    }
    
        
    private func loadData() async {
        guard let userId = authManager.user?.uid else { return }
        
        // Load partner info
        if let (partnerId, partnerName) = try? await firestoreManager.getPartnerData(userId: userId) {
            self.partnerId = partnerId
            self.partnerName = partnerName ?? "Partner"
        }
        
        let days = settingsManager.settings.averagingPeriodDays
        let today = Date()
        let calendar = Calendar.current
        
        // Determine if we should show today's or yesterday's score
        let currentHour = calendar.component(.hour, from: today)
        let startIndex = currentHour >= 16 ? 0 : 1 // Start from today if after 4 PM, otherwise yesterday
        
        // Check if oldest required day has data
        let oldestDate = calendar.date(byAdding: .day, value: -days, to: today)!
        if let _ = try? await firestoreManager.getComputedData(userId: userId, metric: .bandwidth, date: oldestDate) {
            needsHistoricalCalculation = false
        } else {
            needsHistoricalCalculation = true
            if !hasShownInitialLoadAlert {
                await MainActor.run {
                    showInitialLoadAlert = true
                    hasShownInitialLoadAlert = true
                }
            }
        }
        
        // Calculate baseline once if needed
        let baselineMetrics = needsHistoricalCalculation ?
            try? await healthDataProcessor.getBaselineMetrics() : nil
        
        // Load user scores
        var userScores: [Double] = []
        for daysAgo in startIndex...(days + startIndex) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            if let score = try? await firestoreManager.getComputedData(userId: userId, metric: .bandwidth, date: date) {
                userScores.append(score)
            } else {
                // Calculate and store if missing, using the cached baseline
                let calculatedScore = try? await healthDataProcessor.calculateBandwidthScore(
                    for: date,
                    baselineMetrics: healthDataProcessor.getBaselineMetrics()
                )
                if let score = calculatedScore {
                    try? await firestoreManager.storeComputedData(
                        userId: userId,
                        metric: .bandwidth,
                        date: date,
                        value: score
                    )
                    userScores.append(score)
                }
            }
        }
        
        // Load partner scores (fetch only)
        var partnerScores: [Double] = []
        if let partnerId = partnerId {
            for daysAgo in startIndex...(days + startIndex) {
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
                if let score = try? await firestoreManager.getComputedData(userId: partnerId, metric: .bandwidth, date: date) {
                    partnerScores.append(score)
                }
            }
        }
        
        // Update UI
        await MainActor.run {
            self.userScores = userScores
            self.partnerScores = partnerScores
            self.isLoading = false
        }
    }    }

    // Helper struct for score statistics
    struct ScoreStats {
        let latest: Double
        let average: Double
        let max: Double
        let min: Double
        
        init(scores: [Double]) {
            self.latest = scores.first ?? 0
            self.average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            self.max = scores.max() ?? 100
            self.min = scores.min() ?? 0
        }
    }


