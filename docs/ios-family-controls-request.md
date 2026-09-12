# iOS Family Controls Entitlement Request Draft

**Submission Status:** Phase 0 (pre-release)  
**Target iOS Versions:** iOS 16.0 and later  
**Authorization Model:** Individual (self) authorization, not parental control

---

## Application Overview

**App Name:** KUNIM (Muslim Planner)  
**Primary Purpose:** KUNIM is a comprehensive personal life assistant for Muslims that combines daily planning, prayer times, Qur'an reading, habits, wellness tracking, education, and digital wellbeing features into one integrated experience. The Digital Wellbeing component helps users understand and optimize their device usage patterns through screen time monitoring and self-reflection tools.

**App URL:** [TO FILL: App Store Connect app record]  
**Bundle ID:** [TO FILL: Bundle ID]  
**Apple Developer Team ID:** [TO FILL: Apple Developer Team ID]

---

## Family Controls APIs Requested

KUNIM requires the following Family Controls frameworks to implement Digital Wellbeing screen time monitoring:

### 1. DeviceActivity Framework

**Purpose:** Monitor device usage patterns and collect screen time statistics without blocking functionality.

**Implementation:**
- `DeviceActivityMonitor` extension (named `KunimMonitor`):
  - Monitors screen time events on a daily schedule
  - Triggers local notifications at 80% and 100% of user-set limits
  - Detects when users dismiss warnings or snooze limits
  - Stores events locally only; no data transmitted to app or server
  - Extension memory footprint: ~6 MB (minimal)

**Usage:** Daily screen time collection and threshold notifications enable users to make informed decisions about their device usage without forced blocking.

---

### 2. ManagedSettings Framework

**Purpose:** Issue local notifications when usage thresholds are reached (no shielding in Phase 0).

**Implementation:**
- Local notification generation when user approaches or reaches app time limits
- User action options: Open App / Snooze 15 minutes / Dismiss for Today
- **No shielding or blocking in Phase 0** — shielding will be opt-in in Phase 2+
- Configuration managed via `ManagedSettingsStore` (notifications only, no blocking)

**Usage:** Empowers users with timely awareness of their usage patterns to support self-regulation.

---

### 3. FamilyControls (Authorization Only)

**Purpose:** Request individual authorization from the device owner for screen time monitoring.

**Implementation:**
- `FamilyActivityPicker` presents a selection interface (with sandboxed token)
- User explicitly authorizes KUNIM to monitor screen time
- No bundle IDs or app names are accessible to KUNIM; only an opaque token is returned
- Individual (self) authorization — not parental control; user authorizes for their own device
- **Applies to iOS 16.0+** as per Apple's framework requirements

**Usage:** Ensures explicit user consent before collecting any usage data.

---

## Data Handling

### DeviceActivityReport Extension (`ios/KunimReport/`)

- Displays screen time statistics in a **sandboxed SwiftUI view** only
- Statistics **never leave the extension** — no transmission to app or server
- User can view their statistics within the app's settings, but raw numbers are not logged or transmitted
- Extension runs in a separate process with no direct communication capability to main app

### On-Device Statistics Only

- All screen time data is processed and aggregated on-device
- Daily aggregates (category + minutes only) may be synced to server for cross-device analysis **only if user opts in**
- Individual app names are hashed with a per-user salt before any transmission
- Raw session data **never leaves the device**

### Monthly Privacy Audit

- Users have full control over consent in settings: toggle "Cloud Screen Time Stats"
- Export and deletion features available in app settings
- Audit logs maintain GDPR compliance (7-day grace, then hard delete)

---

## Self-Authorization Model (Individual, Not Parental)

KUNIM uses **individual authorization**:
- The device owner (user) authorizes KUNIM to monitor their own usage
- No parent/child or guardian/ward relationships
- No remote management or supervision features
- User can revoke permission at any time via iOS Settings

**Rationale:** KUNIM is a personal wellness tool designed to help individuals (not parents) understand their own device habits and make intentional usage decisions.

---

## First Release Limitations (Phase 0)

**No Shielding:** ManagedSettingsStore.shield is disabled in the initial release.
- Notifications only: users are informed at 80% and 100% of their set limits
- Actions available: Open / Snooze / Dismiss
- **No app blocking or content filtering**

**Future (Phase 2+):** Optional "Focus Mode" may introduce managed app restriction based on user preference.

---

## Fallback Mode

**Feature Flag:** `dw_ios_mode = full | selfreport`

If the Family Controls entitlement is not approved or revoked:
- KUNIM switches to **self-report mode** (`dw_ios_mode = selfreport`)
- User manually logs app usage and rates its productivity
- All features remain functional; only automatic detection is disabled
- Fallback is transparent to end-user; app does not break

---

## User Benefit

Users gain:
1. **Awareness:** Daily screen time statistics by app category
2. **Intentionality:** Threshold notifications help users notice excessive usage patterns
3. **Control:** Full authority over limits, notifications, and data sharing preferences
4. **Privacy:** No data leaves device without explicit consent; all statistics aggregated locally

---

## Compliance & Privacy

- ✓ Minimal permissions: no microphone, camera, location, or health data
- ✓ No tracking of individual app names on server (hashed only)
- ✓ No behavioral profiling or ad targeting
- ✓ Full export/delete capability (GDPR, CCPA compliant)
- ✓ Privacy label on App Store accurately reflects data practices

---

## Development Status

- Extension code implemented in Swift (iOS/KunimMonitor, iOS/KunimReport)
- Tested on iOS 16.0 simulator and test devices
- Ready for App Review once entitlement is approved

---

## Contact for Questions

[TO FILL: Legal contact / Privacy Officer email]

---

---

## Ozbekcha eslatma (Uzbek Note)

**Talab:** iOS Family Controls entitlement'ini Phase 0'da Apple'ga yuborish talab qilinadi. Entitlement so'rovi 0-bosqich uchun kritik vazifa.

**Muddati:** Apple tasdiqlanishi bir necha hafta yoki oylar vaqt olishi mumkin. Rad etilishi ham mumkin.

**Fallback:** Agar rad etilsa yoki keshiktirilsa, `dw_ios_mode=selfreport` flag bilan iOS self-report rejimu chiqadi. Reliz bunga bog'liq emas — ilova to'liq ishlay beradi, faqat avtomatik screen time aniqlanishi o'chiq bo'ladi.

**Kirish:** Entitlement tekshirilishi kutilayotganda, Flutter kodi Developer Account'iga ko'ra dev rezhimida (Dev Team provisioning profile'i) full Family Controls imkoniyatlari bilan ishlaydi. Public App Store versiyasi entitlement rad etilgunicha chiqmaydi.

**Hisobkitob:** Entitlement qo'shilsa, Phase 0 oxirida ilova App Store'ga tasdiqlanish uchun tayyor. Tasdiq rad etilsa, Phase 1'da selfreport fallback qo'shiladi.
