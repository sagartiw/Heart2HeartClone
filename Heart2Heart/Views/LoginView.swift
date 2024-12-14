//loginview.swift

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var errorMessage = ""
    
    private let buttonWidth: CGFloat = 280
    private let buttonHeight: CGFloat = 44
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.14),
                        Color(red: 0.22, green: 0.16, blue: 0.31)
                    ]), startPoint: .init(x: 0, y: 0), endPoint: .init(x: 1, y: 1)
                ).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                    
                    Image("Title").resizable().aspectRatio(contentMode: .fit).frame(width: 300)
                    
                    Spacer()
                            .frame(height: 20)
                    
                    VStack(spacing: 20) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Sign In") {
                            Task {
                                do {
                                    try await authManager.signIn(email: email, password: password)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(Color(red:0.894,green: 0.949, blue: 0.839))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                        
                        Button("Create Account") {
                            showSignUp = true
                        }
                        .foregroundColor(.gray)
                        .cornerRadius(8)
                        
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .font(.custom("KulimPark-SemiBold", size: 18))
                    .sheet(isPresented: $showSignUp) {
                        SignUpView()
                            .environmentObject(authManager)
                    }
                }
                
            }
        }
    }
}
