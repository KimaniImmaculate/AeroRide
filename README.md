# AeroRide 🚗
### Premium, AI-Native, Real-Time Ride-Hailing Platform

AeroRide is a next-generation, premium ride-hailing application designed with a sleek dark-theme aesthetic, role-based safety dashboards, real-time tracking, hands-free Gemini AI voice operations, and integrated payments.



## Live Deployments

| Resource | URL |
|---|---|
| 🌍 **Landing Website** | [ckimeu323-afk.github.io/aeroride](https://ckimeu323-afk.github.io/aeroride/) |
| 📱 **Web Application** | [aeroride-665af.web.app](https://aeroride-665af.web.app) |

> 💡 *The landing website features a **"Get Started"** call-to-action button that transitions directly to the web app portal.*


## Rider-Side Features
* **Guest Exploration & Routing:** Input pickup and dropoff locations to fetch instant route previews and directions on Google Maps without being logged in.
* **Vehicle Tier & Price Comparison:** Browse multiple vehicle tiers (`Tulia` for budget, `Nuru` for comfort, `Pamoja` for group, and `Waziri` for premium) to compare estimated fares based on distance.
* **Fare Confirmation Gate:** A confirmation modal presents route details (from Location X to Y, Tier Z, and calculated fare) with **"Yes, Proceed"** or **"No, Reject"** options before a booking request is sent.
* **Hands-Free Gemini AI Booking:** Record voice instructions in Swahili, English, or local Sheng (e.g. *"Nipee pamoja hadi Westlands niko na wathii watatu"*) to book, cancel, or trigger SOS alerts.
* **Secured OTP Login Gate:** Guests are prompted to sign in via 2FA OTP *only* after confirming their selection. Captcha container collapses automatically once logged in.
* **Live Driver Tracking & Auto-Framing:** Watch the approaching driver's location on the map in real-time. The map auto-frames bounds to keep the passenger, driver, and destination in view.
* **Interactive Ride Cancellation:** Cancel an active request or accepted trip through an in-app dialog where the rider can input a cancellation reason.
* **Smart Cancellation Fees:** Cancelling a matched ride automatically applies a fee equivalent to the base fare of the selected tier (KES 150 - 700). The rider must clear this fee via M-Pesa before requesting another ride.
* **Text-to-Speech Status Updates:** Hear real-time voice updates as the trip state changes (e.g., *"Driver is on the way"*, *"Trip completed"*, *"Trip cancelled"*).
* **Real-Time Active Ride Chat:** Exchange instant messages with the assigned driver, featuring real-time unread message badges.
* **Emergency SOS System:** Trigger quick SOS alerts to the Admin dashboard via voice command or red alert button.
* **IntaSend & M-Pesa Payments:** Pay cancellation fees or trip fares using an interactive M-Pesa STK sandbox prompt.
* **Driver Rating & Reviews:** Submit star ratings (out of 5) for drivers at the end of each trip.


##  Driver-Side Features
* **Online/Offline Duty Toggle:** Switch online availability to start receiving passenger ride requests or go off-duty.
* **Real-Time Dispatch Alerts:** Receive instant ride alerts corresponding to their designated vehicle tier (`Tulia`, `Nuru`, `Pamoja`, or `Waziri`).
* **Synthesized Audio Chime:** Hear a browser-synthesized double-tone chime sound (A5 followed by C6) using the Web Audio API as soon as a new request is dispatched.
* **Interactive Navigation Guide:** Follow live map coordinates from current location to pickup point, and then to the destination.
* **Trip State Machine Controls:** Manage the active trip lifecycle with simple button controls to Accept, Start, and Complete the ride.
* **Trip Cancellation:** Cancel accepted trips due to unavoidable delays or passenger mismatch, returning the rider back to active search.
* **Real-Time Rider Chat:** Coordinate pickup details with passengers directly via in-app messaging with unread counter badges.
* **Driver Wallet Dashboard:** Track total trips, platform commissions, and check active earnings credited directly from completed rides, including **100% payout of passenger cancellation fees** automatically credited to the wallet.
* **Profile Verification Requests:** Submit changes for vehicle registrations, licenses, or tiers to the Admin dashboard for approval.


##  Admin-Side Features
* **Driver Provisioning & Gatekeeping:** Register and authorize new driver accounts directly from the console to prevent unverified operator registration.
* **Real-Time SOS Dispatch Center:** Monitor active emergency alerts in real-time, flashing red warning banners on the dashboard for immediate action.
* **Driver Profile Approvals Console:** Review, accept, or reject pending profile modification updates submitted by drivers (license number, passport photo, vehicle tier).
* **Platform Operations & Financial Monitoring:** Audit overall platform commission collection, inspect total completed trips, and analyze payout streams.


##  Technology Stack
* **Core SDK:** Flutter (Web & Mobile platforms)
* **Backend Databases:** Cloud Firestore (Structured schemas, custom composite indexes, rule guards)
* **API Integration:** Google Maps Flutter SDK, Google Maps Geocoding & Directions API
* **GenAI Engine:** Google Gemini 2.5 Flash
* **Payments:** IntaSend Payment Gateway / M-Pesa STK Web Hooks



##  Database Schema (Firestore Collections)

###  `users`
Tracks driver, rider, and admin metadata.
```json
{
  "name": "Jane Doe",
  "email": "jane@aeroride.com",
  "phone": "+254712345678",
  "role": "driver", // "rider" | "driver" | "admin"
  "carTier": "waziri", // "tulia" | "nuru" | "pamoja" | "waziri"
  "licenseNumber": "DL-987654",
  "bio": "Experienced executive driver.",
  "isOnline": true,
  "latitude": -1.286389,
  "longitude": 36.817223,
  "earnings": 4500.0,
  "cancellationEarnings": 1500.0,
  "totalTrips": 12
}
```

###  `rides`
Maintains the state machine of all trip requests.
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
  "unreadRiderCount": 0,
  "unreadDriverCount": 1,
  "paymentStatus": "pending", // "pending" | "paid" | "failed"
  "mpesaReference": "OJI4HJG8D"
}
```


##  Security Rules (`firestore.rules`)
Firestore read/write accesses are gated using custom rule declarations:
1. **Profile Privacy:** Users can only view and update their own profile document details.
2. **Trip State Modification:** Only the assigned driver can transition a trip from `accepted` to `started` or `completed`.
3. **Chat Security:** Messages can only be read or written by the specific rider and driver assigned to the parent trip.

---

##  Getting Started

### 1. Configure Environment Keys
Define your Gemini API key inside your build environment or pass it dynamically:
```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_GEMINI_KEY
```

### 2. Run the Application
To launch the Flutter client locally:
```bash
flutter run -d chrome
```
