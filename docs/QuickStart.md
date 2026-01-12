# Quick Start Guide

Get started with MachScope in 5 minutes.

## Build MachScope

```bash
cd MachScope
swift build
```

## Your First Parse

Parse the `/bin/ls` command:

```bash
swift run machscope parse /bin/ls
```

Output:
```
=== Mach-O Binary Analysis ===
File: /bin/ls
Size: 151.00 KB

--- Mach Header ---
  Magic:        0xFEEDFACF
  CPU Type:     arm64
  CPU Subtype:  arm64e
  File Type:    Executable
  Load Cmds:    20
  ...
```

## Parse a macOS Application

macOS apps are bundles. The executable is inside:

```bash
# Parse Calculator
swift run machscope parse /System/Applications/Calculator.app/Contents/MacOS/Calculator

# Parse Safari
swift run machscope parse /Applications/Safari.app/Contents/MacOS/Safari
```

## Common Tasks

### View All Information

```bash
swift run machscope parse /bin/ls --all
```

### View Specific Sections

```bash
# Symbols only
swift run machscope parse /bin/ls --symbols

# Dynamic libraries
swift run machscope parse /bin/ls --dylibs

# Strings in binary
swift run machscope parse /bin/ls --strings

# Code signature
swift run machscope parse /bin/ls --signatures

# Entitlements
swift run machscope parse /bin/ls --entitlements
```

### JSON Output

```bash
swift run machscope parse /bin/ls --json
swift run machscope parse /bin/ls --json --all > analysis.json
```

### List Functions in a Binary

```bash
swift run machscope disasm /bin/ls --list-functions
```

### Disassemble Code

```bash
# Disassemble __text section
swift run machscope disasm /bin/ls

# Disassemble from specific address
swift run machscope disasm /bin/ls --address 0x100003f40 --length 50
```

### Check System Permissions

```bash
swift run machscope check-permissions
```

Output shows what features are available:
```
Feature               Status      Notes
------------------------------------------------------------
Static Analysis       ✓ Ready     No special permissions needed
Disassembly           ✓ Ready     No special permissions needed
Debugger              ✗ Denied    Missing debugger entitlement
```

## Parsing Universal (Fat) Binaries

For Universal binaries with multiple architectures:

```bash
# Parse arm64 slice (default)
swift run machscope parse /path/to/fat_binary

# Parse x86_64 slice
swift run machscope parse /path/to/fat_binary --arch x86_64
```

## Output Options

### Colored Output

```bash
# Force colors (even when piping)
swift run machscope parse /bin/ls --color always

# Disable colors
swift run machscope parse /bin/ls --color never

# Auto-detect (default)
swift run machscope parse /bin/ls --color auto
```

### Environment Variables

```bash
# Disable colors globally
export NO_COLOR=1
swift run machscope parse /bin/ls
```

## Help and Version

```bash
# Show help
swift run machscope --help

# Show version
swift run machscope --version

# Command-specific help
swift run machscope parse
swift run machscope disasm
```

## Next Steps

- [Usage Guide](Usage.md) - Complete command reference
- [Architecture](Architecture.md) - Understanding MachScope internals
- [API Reference](API.md) - Using MachScope as a library
