//Heart2Heart.swift
import SwiftUI
import Firebase
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import BackgroundTasks


@main
struct Heart2Heart: App {
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var healthDataProcessor: HealthDataProcessor
    @StateObject private var dailyTaskManager: DailyTaskManager
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    
    init() {
        FirebaseApp.configure()
        
        
        let auth = AuthenticationManager()
        let settings = SettingsManager()
        
        _authManager = StateObject(wrappedValue: auth)
        _settingsManager = StateObject(wrappedValue: settings)
        
        let health = HealthDataProcessor(
            settingsManager: settings,
            authManager: auth
        )
        _healthDataProcessor = StateObject(wrappedValue: health)
        
        let dailyTask = DailyTaskManager(
            healthDataProcessor: health,
            settingsManager: settings
        )

        _dailyTaskManager = StateObject(wrappedValue: dailyTask)
        
        configureUIAppearance()
        
        //requestNotificationPermissions()

    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permissions: \(error.localizedDescription)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(settingsManager)
                .environmentObject(healthDataProcessor)
                .environmentObject(dailyTaskManager)
                .task {
                    await initializeHealthKit()
                }
                .onChange(of: authManager.isAuthenticated) { isAuthenticated in
                    print("Auth state changed: \(isAuthenticated)") 
                    if isAuthenticated {
                        setupNotificationObserver()
                    }
                }
        }
    }
    
    
    private func setupNotificationObserver() {
        print("Setting up notification observer")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ProcessDailyTask"),
            object: nil,
            queue: .main
        ) { notification in
            print("Received ProcessDailyTask notification")
            if let userInfo = notification.userInfo {
                print("Calling handlePushNotification with userInfo:", userInfo) // Add this
                dailyTaskManager.handlePushNotification(userInfo: userInfo)
            }
        }
    }
    
    private func initializeHealthKit() async {
        do {
            try await healthDataProcessor.initialize()
            print("HealthKit initialized successfully")
        } catch {
            print("HealthKit initialization failed: \(error.localizedDescription)")
        }
    }
    
    private func configureUIAppearance() {
        let kulimParkSemiBold = "KulimPark-SemiBold"
        
        UILabel.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UITextField.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UITextView.appearance().font = UIFont(name: kulimParkSemiBold, size: 16)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(name: kulimParkSemiBold, size: 34)!
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(name: kulimParkSemiBold, size: 17)!
        ]
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    private enum Constants {
        static let backgroundTaskIdentifier = "com.Jackson.Heart2Heart.dailyTask"
        static let dailyTaskType = "dailyTask"
        static let processDailyTaskNotification = "ProcessDailyTask"
        static let minimumBackgroundInterval: TimeInterval = 120 // 2 minutes
    }
    
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        setupBackgroundProcessing(application)
        setupNotifications(application)
        setupMessaging()
        registerBackgroundTasks()
        
        return true
    }
    
    // MARK: - Setup Methods
    
    private func setupBackgroundProcessing(_ application: UIApplication) {
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    }
    
    private func setupNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }
    
    private func setupMessaging() {
        Messaging.messaging().delegate = self
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    
    // MARK: - Push Notification Handling
    
    func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication,
                    didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(_ application: UIApplication,
                    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        guard let type = userInfo["type"] as? String,
              type == Constants.dailyTaskType else {
            completionHandler(.noData)
            return
        }
        
        let backgroundTask = application.beginBackgroundTask {
            completionHandler(.failed)
        }
        
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second for processing
                handleNotification(userInfo: userInfo)
                completionHandler(.newData)
            } catch {
                completionHandler(.failed)
            }
            application.endBackgroundTask(backgroundTask)
        }
    }
    
    // MARK: - Background Task Handling
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleNextBackgroundTask()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        handleNotification(userInfo: ["type": Constants.dailyTaskType])
        task.setTaskCompleted(success: true)
    }
    
    private func scheduleNextBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: Constants.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Constants.minimumBackgroundInterval)
        
        try? BGTaskScheduler.shared.submit(request)
    }
    
    // MARK: - Notification Center Delegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handleNotification(userInfo: notification.request.content.userInfo)
        completionHandler([[.banner, .sound]])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        handleNotification(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
    
    // MARK: - Messaging Delegate
    
    func messaging(_ messaging: Messaging,
                  didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken,
              let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            try? await Firestore.firestore()
                .collection("users")
                .document(userId)
                .updateData(["fcmToken": token])
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String,
              type == Constants.dailyTaskType else { return }
        
        NotificationCenter.default.post(
            name: NSNotification.Name(Constants.processDailyTaskNotification),
            object: nil,
            userInfo: userInfo
        )
    }
}
    
