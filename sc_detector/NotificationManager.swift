//
//  NotificationManager.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/8/26.
//

import UserNotifications

class NotificationManager: NSObject {
    override init() {
        super.init()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { wasAuthorized, error in
            if let error {
                Logger.shared.error("Notification auth error: \(error.localizedDescription)")
            } else {
                Logger.shared.info("Notification auth: \(wasAuthorized ? "granted" : "denied")")
            }
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    func sendLocalNotification(title: String, subtitle: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleLocalNotification(title: String, subtitle: String, date: Date) {
        Logger.shared.info("Scheduling notification for \(date): \(title)")
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func clearAllScheduledNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
