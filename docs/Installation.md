# Installation Guide

## Prerequisites

- **macOS**: 14.0 (Sonoma) or later
- **Swift**: 6.0 or later
- **Xcode**: 16.0 or later (includes Swift compiler)
- **Architecture**: ARM64 (Apple Silicon)

### Verify Prerequisites

```bash
# Check macOS version
sw_vers

# Check Swift version
swift --version

# Check Xcode version
xcodebuild -version
```

## Building from Source

### 1. Clone the Repository

```bash
git clone https://github.com/your-repo/MachScope.git
cd MachScope
```

### 2. Build Debug Version

```bash
swift build
```

The debug binary is located at `.build/debug/machscope`.

### 3. Build Release Version

```bash
swift build -c release
```

The release binary is located at `.build/release/machscope`.

### 4. Run Tests

```bash
swift test
```

## Installation Options

### Option 1: Run from Build Directory

```bash
# Run directly with swift run
swift run machscope parse /bin/ls

# Or use the built binary
.build/debug/machscope parse /bin/ls
```

### Option 2: Install to /usr/local/bin

```bash
# Build release version
swift build -c release

# Copy to /usr/local/bin
sudo cp .build/release/machscope /usr/local/bin/

# Verify installation
machscope --version
```

### Option 3: Create Alias

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias machscope='/path/to/MachScope/.build/release/machscope'
```

## Enabling Debugging Features

To use the `debug` command, MachScope needs the debugger entitlement.

### 1. Sign with Entitlements

```bash
# Build first
swift build

# Sign with debugger entitlement
codesign --force --sign - \
  --entitlements Resources/MachScope.entitlements \
  .build/debug/machscope
```

### 2. Enable Developer Tools

1. Open **System Settings**
2. Go to **Privacy & Security** > **Developer Tools**
3. Enable **Terminal** (or your terminal app)
4. Restart Terminal

### 3. Verify Permissions

```bash
swift run machscope check-permissions
```

You should see:
```
Debugger              ✓ Ready
```

## Uninstallation

### If Installed to /usr/local/bin

```bash
sudo rm /usr/local/bin/machscope
```

### Remove Build Artifacts

```bash
swift package clean
rm -rf .build
```

## Troubleshooting Installation

### Swift Not Found

Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### Build Fails with Module Errors

Clean and rebuild:
```bash
swift package clean
swift build
```

### Permission Denied Errors

Ensure you have read access to the repository:
```bash
ls -la
```

### Code Signing Fails

Make sure you have a valid signing identity:
```bash
security find-identity -v -p codesigning
```

For ad-hoc signing (no certificate needed), use `-` as the identity:
```bash
codesign --force --sign - ...
```

## Next Steps

- [Quick Start Guide](QuickStart.md) - Get started using MachScope
- [Usage Guide](Usage.md) - Complete command reference
