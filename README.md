# MacTrack (Native Remote Trackpad)

MacTrack is a zero-latency, 100% native remote trackpad and keyboard solution for macOS and iOS. It uses pure Swift and Apple's UDP `Network` framework to deliver real-time cursor movements.

## Features
- Ultra-low latency via UDP.
- Native `CGEvent` cursor control on macOS.
- Native `SwiftUI` trackpad interface on iOS.
- No third-party dependencies.

## Structure
- `Server/`: The macOS daemon that receives UDP packets and simulates mouse events. Run via `swift run`.
- `Client/`: The iOS SwiftUI application that captures user gestures and sends them over the local network.

## How to use
1. Find your Mac's local IP address.
2. Run the server on your Mac.
3. Build the iOS app via Xcode and enter your Mac's IP address.
