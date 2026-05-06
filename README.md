# 🛡️ Project Saila: Behavioral Biometrics Demo

> **Zero-Trust Pre-Authentication Engine for FIDO2 Security**

Traditional passwordless authentication (like FIDO2) is vulnerable to high-speed **HID Injection attacks**—where malicious scripts mimic human inputs. The **Project Saila Demo** is a hybrid-native mobile architecture designed to solve this by verifying *how* the user behaves physically, rather than just what credentials they hold.

By capturing micro-vibrations and touch variations, we differentiate between an automated bot and a physical human hand in real-time.

---

## ⚡ Core Features

*   **Touch Dynamics (2D):** Captures high-precision `PointerEvent` data to calculate screen **Dwell Time** (the millisecond variance between touch-down and touch-up). Bots click instantly; humans linger.
*   **Hardware Telemetry (3D):** Architecture mapped for Native Android `SensorManager` integration via Kotlin EventChannels to capture X, Y, Z gyroscope micro-tremors.
*   **Battery-Optimized Lifecycle:** Sensors and listeners are strictly bound to the `FocusNode` of the input fields. Telemetry only records during active typing to prevent battery drain.
*   **Jank-Free UI:** Data streaming is decoupled from the main UI thread to ensure a buttery 60/120 FPS experience during data harvesting.

---

## 🏗️ Tech Stack

*   **Frontend Engine:** Flutter (Dart)
*   **Native Bridge:** Kotlin (MethodChannels & EventChannels)
*   **Data Processing:** Dart Isolates (Background threading)
*   **Target Platform:** Android (API 21+)

---

## 🧠 System Architecture Overview

1.  **Host UI (Flutter):** Renders the secure login portal and wraps input fields in raw coordinate listeners.
2.  **The Bridge (Platform Channels):** A dedicated Kotlin `EventChannel` bypasses Flutter's standard sensor limitations to pull uncompressed data directly from the motherboard.
3.  **The Payload:** The system correlates the Touch Dynamics and Gyroscope variance, packaging it into a synchronized JSON Time-Series array.

---

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK (`v3.10` or higher)
*   Android Studio / VS Code
*   **A physical Android device** *(Note: Touch Dynamics and hardware sensors cannot be accurately tested on an emulator due to uniform mouse-click latency).*

### Installation

1. Clone the repository:
  
