// Views/ContentView.swift
// Views/ContentView.swift
import SwiftUI

enum DisplayMetric: Hashable {
    case healthMetric(HealthMetric)
    case bandwidthScore
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var healthDataProcessor: HealthDataProcessor
    @State private var selectedTab = 1
    
    init() {
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: UIFont(name: "KulimPark-SemiBold", size: 12)!],
            for: .normal
        )
    }
    
    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                LoginView()
            } else if authManager.isOnboarding {
                OnboardingView()
            } else {
                MainTabView(selectedTab: $selectedTab)
            }
        }
    }
}

struct MainTabView: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                CalendarView()
                    .tabItem {
                        Image(systemName: selectedTab == 0 ? "circle.fill" : "circle")
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(0)

                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                    }
                    .tag(1)

                ComponentView()
                    .tabItem {
                        Image(systemName: selectedTab == 2 ?  "circle.fill" : "circle")
                            .environment(\.symbolVariants, .none)
                    }
                    .tag(2)
            }
            .tint(.gray)
            .font(.custom("KulimPark-SemiBold", size: 14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                            .foregroundColor(Color(red:0.894,green: 0.949, blue: 0.839))
                    }
                }
            }
        }
    }
}
