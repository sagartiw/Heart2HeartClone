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
                Color(red: 0.141, green: 0.141, blue: 0.141)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image("Icon")
                        .resizable() 
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                    
                    HStack {
                        VStack(spacing: 10) {
                            Text("Heart")
                                .font(.custom("KulimPark-SemiBold", size: 32))
 
                            Text("2")
                                .font(.custom("KulimPark-SemiBold", size: 32))
                            Text("Heart")
                                .font(.custom("KulimPark-SemiBold", size: 32))
                        }
                    }
                    
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
