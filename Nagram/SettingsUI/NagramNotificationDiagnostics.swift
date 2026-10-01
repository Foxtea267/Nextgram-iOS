import AccountContext
import CoreLocation
import Display
import Foundation
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import UIKit
import UserNotifications

// MARK: NEXTGRAM — Check installed permissions and test local delivery independently of remote push.
func nagramPresentNotificationDiagnostics(context: AccountContext, present: @escaping (ViewController) -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
        Queue.mainQueue().async {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let string: (String) -> String = { ngI18n($0, lang) }
            let enabled = string("Nagram.NotificationDiagnostics.Enabled")
            let disabled = string("Nagram.NotificationDiagnostics.Disabled")
            let notificationAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let locationAllowed = CLLocationManager().authorizationStatus == .authorizedAlways
            let text = String(format: string("Nagram.NotificationDiagnostics.Status"),
                notificationAllowed ? enabled : disabled,
                locationAllowed ? enabled : disabled,
                UIApplication.shared.isRegisteredForRemoteNotifications ? enabled : disabled,
                NagramSettings.shared.localNotificationFallbackEnabled ? enabled : disabled,
                Bundle.main.bundleIdentifier ?? "Nextgram"
            )
            present(textAlertController(context: context, title: string("Nagram.NotificationDiagnostics"), text: text, actions: [
                TextAlertAction(type: .genericAction, title: string("Nagram.NotificationDiagnostics.OpenSettings"), action: {
                    context.sharedContext.applicationBindings.openSettings()
                }),
                TextAlertAction(type: .defaultAction, title: string("Nagram.NotificationDiagnostics.Test"), action: {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in
                        guard allowed else {
                            Queue.mainQueue().async {
                                present(textAlertController(context: context, title: string("Nagram.NotificationDiagnostics.Test"), text: string("Nagram.NotificationDiagnostics.PermissionRequired"), actions: [
                                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                                ]))
                            }
                            return
                        }
                        let content = UNMutableNotificationContent()
                        content.title = "Nextgram"
                        content.body = string("Nagram.NotificationDiagnostics.Test.Body")
                        content.sound = .default
                        let request = UNNotificationRequest(identifier: "nextgram-test-\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5.0, repeats: false))
                        center.add(request) { error in
                            Queue.mainQueue().async {
                                present(textAlertController(context: context, title: string("Nagram.NotificationDiagnostics.Test"), text: string(error == nil ? "Nagram.NotificationDiagnostics.Test.Scheduled" : "Nagram.NotificationDiagnostics.Test.Failed"), actions: [
                                    TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                                ]))
                            }
                        }
                    }
                }),
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {})
            ]))
        }
    }
}
