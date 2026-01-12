# MachScope Documentation

MachScope is a native macOS binary analysis tool providing Mach-O parsing, ARM64 disassembly, and process debugging capabilities. Built entirely in Swift with no external dependencies.

## Table of Contents

1. [Installation](Installation.md) - Build and install MachScope
2. [Quick Start](QuickStart.md) - Get started in 5 minutes
3. [Usage Guide](Usage.md) - Complete command reference
4. [Architecture](Architecture.md) - Technical design and internals
5. [API Reference](API.md) - Using MachScope as a library
6. [Troubleshooting](Troubleshooting.md) - Common issues and solutions
7. [Contributing](Contributing.md) - How to contribute

## Features

### Mach-O Parsing
- Parse single-architecture and Fat/Universal binaries
- Extract headers, load commands, segments, and sections
- Symbol table with lazy loading
- Dynamic library dependencies
- Code signature and entitlements parsing
- String extraction from binary sections

### ARM64 Disassembly
- Full ARM64 instruction decoder
- Data processing, branch, load/store, and system instructions
- PAC (Pointer Authentication) instruction annotation
- Swift symbol demangling
- Symbol resolution for readable output

### Process Debugging
- Attach to running processes
- Set and manage breakpoints
- Single-step execution
- Read/write memory
- Register inspection (x0-x30, sp, pc, cpsr)
- Backtrace generation

### Permission Management
- System Integrity Protection (SIP) detection
- Developer Tools status checking
- Debugger entitlement validation
- Tiered capability reporting

## Requirements

- macOS 14.0 or later
- Swift 6.0 or later
- Xcode 16.0 or later (for development)
- ARM64 (Apple Silicon) processor

## Quick Example

```bash
# Build
swift build

# Parse a binary
swift run machscope parse /bin/ls

# Disassemble
swift run machscope disasm /bin/ls --list-functions

# Check permissions
swift run machscope check-permissions
```

## License

MIT License - See LICENSE file for details.

## Support

- GitHub Issues: Report bugs and feature requests
- Documentation: This docs/ folder
- Source Code: Fully commented Swift code
