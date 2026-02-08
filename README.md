# Tichu

Multiplayer Tichu card game built with Flutter.

## Supported targets
- Linux desktop
- Web

## Prerequisites
- Flutter SDK (stable channel)
- A working C++ toolchain
- Linux build deps: GTK 3 and Ninja
- A Chromium-based browser for web runs

Linux deps (Ubuntu/Debian):
```
sudo apt-get update -y
sudo apt-get install -y ninja-build libgtk-3-dev \
	libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
	lld
```

## Run (end user)
First time only, enable the required platforms:
```
flutter config --enable-linux-desktop --enable-web
```

Get dependencies:
```
flutter pub get
```

Run on Linux:
```
flutter run -d linux
```

Run on Web (Chrome):
```
flutter run -d chrome
```

Run on Web (local web server):
```
flutter run -d web-server --web-port 8080
```

## Build
Linux desktop bundle:
```
flutter build linux
```

Web release bundle:
```
flutter build web
```

## Common tasks
Format code:
```
flutter format --output=none --set-exit-if-changed .
```

Analyze:
```
flutter analyze
```

Run tests:
```
flutter test
```

Clean build outputs:
```
flutter clean
```
