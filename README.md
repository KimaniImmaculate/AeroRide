# AeroRide 🚗
### Premium, AI-Native Ride-Hailing Platform

AeroRide is a next-generation, premium ride-hailing application designed with a focus on dark-theme aesthetics, role-based safety, and hands-free, voice-native operations powered by Google Gemini.

---

## 🔗 Live Links

| | Link |
|---|---|
| 🌍 **Landing Website** | [ckimeu323-afk.github.io/aeroride](https://ckimeu323-afk.github.io/aeroride/) |
| 📱 **Web App** | [aeroride-665af.web.app](https://aeroride-665af.web.app) |

> The landing website includes a **"Get Started"** CTA button that takes you directly to the web app.

---

## 🌟 Key Innovations & USPs

### 1. Multilingual Gemini AI Voice Assistant
Unlike traditional applications that only allow voice typing, AeroRide features a native integration with **Gemini 2.5 Flash** to provide a hands-free booking pipeline:
*   **Multilingual & Sheng Support:** Understands natural speech combining English, Swahili, and local Sheng (e.g., *"Nitume waziri to Westlands, niko na bags"*).
*   **Multi-Intent Parsing:** Automatically determines if the user's goal is to:
    *   **Book:** Extracts pickup, destination, maps the route, calculates fare, and captures custom notes.
    *   **Cancel:** Recognizes cancellation statements and aborts active rides instantly.
    *   **SOS:** Instantly routes safety concerns straight to the Admin panel.
*   **Dynamic Tier Extraction:** Maps requests for luxury/premium, comfort, or group vehicles directly to the correct database tier (`waziri`, `nuru`, `pamoja`, or `tulia`).

### 2. Live Driver Tracking & Auto-Framing Camera
*   **Real-time Map Markers:** Dynamic updates on Google Maps showing the assigned driver (in deep purple/violet) and nearby available drivers (in blue).
*   **Auto-Framing Bounds:** The camera automatically calculates map bounds to dynamically zoom and center the screen, keeping the rider, destination, and approaching driver in view at all times.

### 3. Safety & Emergency Workflows
*   **Voice-Activated SOS:** Instantly writes an emergency log to the `emergencies` database collection and flashes a red alert panel on the Admin dashboard.
*   **Role-Based Security:** Secure Firebase Firestore security rules ensuring only authorized roles can mutate trip data or process records.

### 4. Admin Provisioned Drivers
*   **Anti-Spam Registration:** Driver accounts can only be provisioned by an administrator on the dashboard, preventing unauthorized/unverified operators.
*   **Profile Review:** Driver updates (license changes, vehicle tier changes) are sent as formal request documents to the admin tab for resolution.

---

## 🛠️ Technology Stack
*   **Frontend Framework:** Flutter (supporting Web & Mobile platforms)
*   **Database & Auth:** Google Firebase (Cloud Firestore & Firebase Authentication)
*   **GenAI Engine:** Google Generative AI Dart SDK (Gemini 2.5 Flash)
*   **Map Integrations:** Google Maps Flutter SDK & Google Geocoding API
*   **Payment Integration:** IntaSend Payment Gateway (M-Pesa STK Push & Card payments)

---

## 📂 Database Schema (Firestore Collections)

### 👤 `users`
Represents both riders, drivers, and admins.
```json
{
  "name": "Jane Doe",
  "email": "jane@aeroride.com",
  "phone": "+254712345678",
  "role": "driver", // "rider" | "driver" | "admin"
  "carTier": "waziri", // "tulia" | "nuru" | "pamoja" | "waziri"
  "licenseNumber": "DL-987654",
  "bio": "Experienced executive driver.",
  "passportPhotoUrl": "https://...",
  "isOnline": true,
  "latitude": -1.286389,
  "longitude": 36.817223,
  "earnings": 4500.0,
  "platformEarnings": 1500.0,
  "totalTrips": 12
}
```

### 🚗 `rides`
Tracks the lifecycle of ride requests.
```json
{
  "pickup": "Jomo Kenyatta Airport",
  "destination": "Westlands",
  "status": "searching", // "searching" | "accepted" | "started" | "completed" | "cancelled"
  "rideTier": "waziri",
  "fare": 1850,
  "notes": "I have heavy luggage.",
  "riderId": "rider_uid_123",
  "riderEmail": "rider@aeroride.com",
  "driverId": "driver_uid_987",
  "createdAt": "Timestamp",
  "paymentStatus": "pending",
  "paymentMethod": "M-Pesa"
}
```

### 🚨 `emergencies`
Routes SOS events directly to the admin.
```json
{
  "type": "SOS",
  "userRole": "rider", // "rider" | "driver"
  "userId": "rider_uid_123",
  "message": "Emergency: suspicious activity.",
  "status": "active", // "active" | "resolved"
  "createdAt": "Timestamp"
}
```

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have the Flutter SDK installed on your machine.

### 2. Configure Environment Keys
Define your Gemini API key inside your build environment or pass it dynamically:
```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_GEMINI_KEY
```

### 3. Run the Application
To launch the Flutter web client locally:
```bash
flutter run -d chrome
```

---

## 🔒 Security Rules (`firestore.rules`)
Firestore data is secured with strict validation rules ensuring that:
1.  Users can only read and write their own profile document.
2.  Riders can request rides, but only assigned drivers can update a ride status to `accepted`, `started`, or `completed`.
3.  Ride tiers must belong to the approved set: `['tulia', 'nuru', 'pamoja', 'waziri']`.
