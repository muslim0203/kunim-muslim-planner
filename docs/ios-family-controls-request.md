# iOS Family Controls Entitlement Request

Status: DRAFT — not submitted. Updated 2026-09-12.

## Account details required before submission

- Apple Developer Account Holder: [TO FILL from signed-in account]
- Developer Team ID: [TO FILL from signed-in account]
- App Bundle ID: [TO FILL after registering the actual identifier]
- Monitor/report extension identifiers: [TO FILL if required by Apple's current request workflow]
- Contact email: [TO FILL with account holder's confirmed contact]
- App Store Connect record: [TO FILL if created and requested by the form]

Do not invent these values. Use the current Apple form to determine required fields.

## Proposed request text

KUNIM (Muslim Planner) is an early-stage personal planning and wellbeing application for iOS 16 and later. It combines daily planning, habits, prayer and Quran routines, and voluntary digital wellbeing tools.

We request Family Controls distribution access for a planned, user-controlled Screen Time feature. The device owner will authorize access using individual authorization and select applications or categories through FamilyActivityPicker. This is a self-management experience, without parent/child supervision or remote management.

We plan to implement a DeviceActivityMonitor extension to receive threshold callbacks at 80% and 100% of user-configured daily limits. Subject to notification authorization and device validation, these callbacks will support local reminders. Reminder actions will be handled through UserNotifications and application logic; ManagedSettings is not a notification API. The first release will not shield or block applications.

A DeviceActivityReport extension will render usage information in its privacy-preserving report view. We will not extract report data into the main application, upload it, or use it for AI profiling. We will not attempt to resolve opaque selection tokens into application identities in the main application. Any supported local monitor coordination will remain distinct from report data and will be validated on a physical device.

Users can decline or revoke authorization. A manual self-report mode will remain available without Screen Time access. Core planning features will continue to work without this permission. No other application's content will be read, and Screen Time data will not be used for advertising.

The feature is currently planned, not implemented or device-tested. The repository contains only an initial iOS host scaffold; monitor and report extensions, signing configuration, and physical-device validation remain outstanding. We are requesting access early so distribution approval can be addressed during development.

## Submission and verification notes

1. Sign in as the Apple Developer Account Holder and verify active team membership.
2. Open Apple's current Family Controls distribution request workflow and enter verified account/application details.
3. Submit the factual development-stage description above if the form requests a description. Follow the current workflow for app and extension identifiers.
4. Record the submission date and request/reference ID here only after Apple confirms receipt.
5. Approval does not establish that implementation, device tests, or App Store review are complete.

Submission date: not submitted.
Request/reference ID: none.

## References

- https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- https://developer.apple.com/contact/request/family-controls-distribution
- https://developer.apple.com/documentation/managedsettings
- https://developer.apple.com/documentation/deviceactivity/deviceactivityreportextension

## O'zbekcha holat

Oldingi matndagi “Swift extensionlar yozilgan”, “simulator va real qurilmada sinalgan” va “App Review uchun tayyor” da'volari repository bilan tasdiqlanmadi va olib tashlandi. ManagedSettings orqali bildirishnoma yuborish haqidagi xato tuzatildi. iOS report ma'lumotlarini serverga yuborish taklifi olib tashlandi. Apple akkauntiga kirish va haqiqiy akkaunt identifikatorlari kerak; ariza hali yuborilmagan.

Account verification: Apple Developer Agreement accepted with explicit user confirmation on 2026-09-12. Portal offers Program enrollment; Family Controls request returned Unauthorized. Enrollment is waiting for legal identity/contact/address input. No payment or entitlement submission made.
