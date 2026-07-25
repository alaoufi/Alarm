# Google Play — Data Safety form answers (Alerts)

Use these answers in Play Console → App content → Data safety.

## Does your app collect or share any of the required user data types?
**No** — the developer does not collect or receive any user data. All data
(reminders, notes, medication, settings) is stored **locally on the device**.

- **Data collected by the developer:** None.
- **Data shared with third parties:** None.
- **Data sold:** No.

## Optional Google Drive sync
If the user enables cloud sync, an **encrypted copy** of their data is stored in
**the user's own Google Drive** (app data folder). This is user-initiated,
goes only to the user's own account, and is **not accessible to the developer**.
Because the developer neither collects nor receives it, it is not declared as
developer data collection. (If the Console review asks: data is transferred to
the user's own cloud storage, encrypted, user-controlled, deletable.)

## Payments
Subscriptions are processed by **Google Play Billing**. The developer does not
receive or store payment information.

## Security practices
- **Data encrypted in transit:** Yes (Google Drive uses HTTPS; backups are
  encrypted before upload).
- **Data encrypted at rest on device:** Yes (secure storage / encrypted DB).
- **Users can request data deletion:** Yes — uninstalling or clearing app data
  removes all local data; deleting the Drive backup removes the cloud copy.

## Account creation
The app does **not** require creating an account to use it (10-day trial opens
the full app immediately). Google sign-in is used **only** if the user turns on
optional Drive sync.

## Data types summary (all = Not collected by developer)
- Personal info (name, email, etc.): Not collected by developer.
- Financial info: Handled by Google Play only.
- Health (medication reminders): Stored on-device only; not collected.
- App activity / content (notes, reminders): Stored on-device / user's Drive;
  not collected by developer.
- Audio (voice notes): Stored on-device only; not collected.
