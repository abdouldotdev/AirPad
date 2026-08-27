# Notes de review App Store

Poussées dans `App Review Information → Notes` via le MCP `appstore-connect`
(`review_detail_set`). Une vidéo de démonstration est jointe séparément
(`review_attachments_upload`).

> **Pourquoi ce texte est long** : le reviewer n'aura pas de Mac appairé.
> Sans mode d'emploi, il ouvre l'app, voit un écran d'appairage, et rejette
> pour « fonctionnalité incomplète ». C'est le motif de rejet n°1 pour ce type
> d'app. Chaque étape ci-dessous existe pour lui éviter ça.

---

```
IMPORTANT — AirPad needs a companion Mac app to do anything.

Without a paired Mac, the app can only show its pairing screen. Everything
below takes about two minutes and lets you exercise the full app. A demo
video is attached to this submission as well.

1. INSTALL THE FREE MAC COMPANION
   https://github.com/abdouldotdev/AirPad/releases/download/v1.0.0/AirPad-1.0.0.dmg
   The app is signed with our Developer ID and notarized by Apple.
   Open the DMG, drag AirPad into Applications, and launch it.

2. GRANT ACCESSIBILITY ACCESS ON THE MAC
   System Settings > Privacy & Security > Accessibility > enable AirPad.
   macOS requires this for any app that moves the pointer or types on the
   user's behalf. The Mac app shows a banner and a direct link until it is
   granted. Without it, macOS silently ignores the events.

3. START PAIRING
   The Mac app lives in the menu bar (it has no Dock icon). Click its icon,
   then "Start Pairing". A window shows a QR code, the Mac's local IP
   address, the port, and an 8-character pairing code.

4. PAIR FROM THE iPhone OR iPad
   Launch AirPad, go through the 3 onboarding screens, tap "Pair my Mac".
   Either scan the QR code with the camera, or tap "Or enter IP and code
   manually" and type the IP address, port 8080, and the 8-character code
   displayed on the Mac.

5. USE IT
   Drag on the grey trackpad area to move the Mac pointer. Tap to click.
   "Left Click" and "Right Click" buttons are at the bottom. Two fingers
   scroll. The keyboard is a paid feature (see below).

BOTH DEVICES MUST BE ON THE SAME WI-FI NETWORK.
AirPad opens a plain TCP socket to the Mac on the local network. It makes no
internet connection for its core function. Pairing is protected by the
8-character code, which is never transmitted over the internet and is shown
only on the Mac's own screen — this prevents anyone else on the same Wi-Fi
from taking control.

IN-APP PURCHASE — WHAT IS FREE AND WHAT IS PAID
The trackpad (pointer, clicks, scrolling) is free and stays free.
AirPad Pro, an auto-renewable subscription, unlocks:
  - the on-screen keyboard (QWERTY and AZERTY) with Shift/Command/Option/Control
  - the F1-F12 function row
  - adjustable pointer speed
  - three- and four-finger gestures
  - switching between several paired Macs
This split is stated explicitly in the App Store description.
To reach the paywall without a Mac: Settings (gear, top right) > "Get AirPad Pro".

PERMISSIONS THE APP ASKS FOR
  - Camera: only to scan the QR pairing code. Declining it leaves the manual
    pairing path fully working; the app explains this instead of failing.
  - Local Network: required to reach the Mac. Nothing is sent to the internet.

NO ACCOUNT IS REQUIRED. There is no login, and we collect no personal data.
Privacy policy: https://abdouldotdev.github.io/AirPad/privacy.html
```

---

## Demandes de contact

| Champ | Valeur |
|---|---|
| Prénom / Nom | Abdoul Rachid Tapsoba |
| E-mail | hey@abdoul.dev |
| Téléphone | *à renseigner par l'utilisateur* |

Pas de compte de démonstration nécessaire (`demo account required: false`).
