//Views/OnboardingView.swift

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var currentStep = 0
    @State private var isPresented = true
    
    private let buttonWidth: CGFloat = 280
    private let buttonHeight: CGFloat = 44
    private let buttonColor = Color(uiColor: UIColor.systemGray5)
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.08, blue: 0.14),
                    Color(red: 0.22, green: 0.16, blue: 0.31)
                ]), startPoint: .init(x: 0, y: 0), endPoint: .init(x: 1, y: 1)
            ).ignoresSafeArea()
            
            VStack{
                
                Image("Logo")
                    .resizable() 
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                
                Group {
                    if currentStep == 0 {
                        notificationPermissionContent
                    } else {
                        PartnerInvitationView(isPresented: $isPresented)
                            .onChange(of: isPresented) { newValue in
                                if !newValue {
                                    authManager.completeOnboarding()
                                }
                            }
                    }
                }
                .font(.custom("KulimPark-SemiBold", size: 14))
            }
        }
    }
    
    private var notificationPermissionContent: some View {
        VStack(spacing: 20) {
            Text("Stay in touch")
                .font(.custom("KulimPark-SemiBold", size: 32))
            
            Text("To get the most out of Heart2Heart, enable notifications and receive updates about your partner's emotional well-being")
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Enable Notifications") {
                requestNotificationPermission()
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .background(Color(red:0.894,green: 0.949, blue: 0.839))
            .foregroundColor(.black)
            .cornerRadius(8)
            
            Button("Skip") {
                currentStep += 1
            }
            .foregroundColor(.gray)
            .cornerRadius(8)
        }
        .padding()
    }
    
    private func requestNotificationPermission() {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if authManager.isAuthenticated {
                        currentStep += 1
                    }
                }
            }
        }
}
