//partnerInvitationView.swift
import SwiftUI
import Firebase

struct PartnerInvitationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    
    @State private var showInvitationCode = false
    @State private var showShareSheet = false
    @State private var invitationCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showGeneratedCode = false
    @State private var isLoading = false
    
    private let buttonColor = Color(red: 0.894, green: 0.949, blue: 0.839)
    private let standardButtonWidth: CGFloat = 200
    private let standardButtonHeight: CGFloat = 30
    
    var body: some View {
            VStack(spacing: 20) {
                headerSection
                
                if showGeneratedCode {
                    codeDisplaySection
                } else {
                    buttonSection
                }
            }
            .padding()
            .sheet(isPresented: $showInvitationCode) {
                        InvitationCodeView(isPresented: $showInvitationCode,
                                         parentIsPresented: $isPresented)
                    }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                authManager.completeOnboarding()
                isPresented = false
            }) {
                ShareSheet(activityItems: ["Join me on H2H! Here's your invitation code: \(invitationCode)"])
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        }
    
    private var headerSection: some View {
            VStack {
                Text("Partner Pairing")
                    .font(.custom("KulimPark-SemiBold", size: 24))
                Text("Heart 2 Heart works best with a partner.")
                    .font(.custom("KulimPark-SemiBold", size: 14))
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        
    private var codeDisplaySection: some View {
            VStack(spacing: 40) { // Increased spacing
                VStack(spacing: 20) {
                    Text("Your Invitation Code:")
                        .font(.custom("KulimPark-SemiBold", size: 14))
                    
                    codeDisplay
                }
                
                Button("Share Code") {
                    showShareSheet = true
                }
                .font(.custom("KulimPark-SemiBold", size: 14))
                .frame(width: standardButtonWidth, height: standardButtonHeight)
                .background(buttonColor)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
        }
    
        private var codeDisplay: some View {
            HStack(spacing: 20) {
                ForEach(0..<2) { group in
                    HStack(spacing: 8) {
                        ForEach(0..<3) { digit in
                            let index = group * 3 + digit
                            digitView(for: index)
                        }
                    }
                }
            }
        }
        
        private func digitView(for index: Int) -> some View {
            Text(String(invitationCode[invitationCode.index(invitationCode.startIndex, offsetBy: index)]))
                .font(.custom("KulimPark-SemiBold", size: 32))
                .frame(width: 50, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonColor, lineWidth: 2)
                )
        }
        
        private var buttonSection: some View {
            VStack(spacing: 20) {
                Button("Invite My Partner") {
                    generateInvitationCode()
                }
                .font(.custom("KulimPark-SemiBold", size: 14))
                .frame(width: standardButtonWidth, height: standardButtonHeight)
                .background(buttonColor)
                .foregroundColor(.black)
                .cornerRadius(10)
                
                Button("My Partner Invited Me") {
                    showInvitationCode = true
                }
                .font(.custom("KulimPark-SemiBold", size: 14))
                .frame(width: standardButtonWidth, height: standardButtonHeight)
                .background(buttonColor)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
        }
    
    
    private func generateInvitationCode() {
        isLoading = true
        Task {
            do {
                invitationCode = try await authManager.generateInvitationCode()
                await MainActor.run {
                    showGeneratedCode = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

// Helper View for sharing
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
