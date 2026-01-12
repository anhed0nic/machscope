# Usage Guide

Complete reference for all MachScope commands and options.

## Global Options

These options work with any command:

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | `-v` | Show version information |
| `--json` | `-j` | Output in JSON format |
| `--color <mode>` | | Color output: auto, always, never |

## Commands

- [parse](#parse-command) - Parse Mach-O binary structure
- [disasm](#disasm-command) - Disassemble ARM64 code
- [check-permissions](#check-permissions-command) - Check system permissions
- [debug](#debug-command) - Attach to running process

---

## Parse Command

Parse and analyze Mach-O binary files.

### Syntax

```bash
machscope parse <binary> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<binary>` | Path to Mach-O binary file |

### Options

| Option | Description |
|--------|-------------|
| `--json`, `-j` | Output in JSON format |
| `--arch <arch>` | Architecture to parse (arm64, x86_64) |
| `--color <mode>` | Color output: auto, always, never |
| `--all` | Show all information |
| `--headers` | Show Mach-O header |
| `--load-commands` | Show load commands summary |
| `--segments` | Show segments and sections |
| `--symbols` | Show symbol table |
| `--strings` | Show extracted strings |
| `--dylibs` | Show dynamic library dependencies |
| `--signatures` | Show code signature information |
| `--entitlements` | Show embedded entitlements |

### Examples

```bash
# Basic parse
machscope parse /bin/ls

# Full analysis
machscope parse /bin/ls --all

# Specific sections
machscope parse /bin/ls --symbols --dylibs

# JSON output
machscope parse /bin/ls --json

# Parse x86_64 slice of Universal binary
machscope parse /path/to/universal --arch x86_64

# Parse macOS application
machscope parse /Applications/Safari.app/Contents/MacOS/Safari

# Save JSON analysis
machscope parse /bin/ls --json --all > analysis.json
```

### Output Sections

#### Header
```
--- Mach Header ---
  Magic:        0xFEEDFACF
  CPU Type:     arm64
  CPU Subtype:  arm64e
  File Type:    Executable
  Load Cmds:    20
  Cmds Size:    1712 bytes
  Flags:        NO_UNDEFS DYLDLINK TWOLEVEL PIE
```

#### Segments
```
--- Segments (5) ---
  __TEXT
    VM Address:  0x0000000100000000
    VM Size:     32.00 KB
    File Size:   32.00 KB
    Protection:  r-x
    Sections (5):
      __text
        Address: 0x0000000100000700
        Size:    14.92 KB
        Type:    regular
```

#### Symbols
```
--- Symbols ---
  Total: 150 (defined: 45, undefined: 105)

  Defined symbols (first 50):
    0x0000000100003F40 T _main
    0x0000000100003F80 t _helper_function
```

#### Code Signature
```
--- Code Signature ---
  Identifier:   com.apple.ls
  Team ID:      (none)
  Flags:        ADHOC
  Hash Type:    SHA256
  CDHash:       abc123...
  Signature:    Ad-hoc (no certificate)
```

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | File not found |
| 2 | Invalid Mach-O format |
| 3 | Unsupported architecture |
| 4 | Parse error (corrupted binary) |

---

## Disasm Command

Disassemble ARM64 code from Mach-O binaries.

### Syntax

```bash
machscope disasm <binary> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<binary>` | Path to Mach-O binary file |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--json` | `-j` | Output in JSON format |
| `--function` | `-f` | Disassemble specific function |
| `--address` | `-a` | Start address for disassembly |
| `--length` | `-l` | Number of instructions (default: 100) |
| `--section` | | Section to disassemble (default: __text) |
| `--show-bytes` | `-b` | Show raw instruction bytes |
| `--no-address` | | Hide instruction addresses |
| `--no-demangle` | | Don't demangle Swift symbols |
| `--no-pac` | | Don't annotate PAC instructions |
| `--list-functions` | | List all functions in binary |

### Examples

```bash
# Disassemble __text section
machscope disasm /bin/ls

# List all functions
machscope disasm /bin/ls --list-functions

# Disassemble specific function
machscope disasm /bin/ls --function _main

# Disassemble from address
machscope disasm /bin/ls --address 0x100003f40 --length 20

# Show instruction bytes
machscope disasm /bin/ls --show-bytes

# JSON output
machscope disasm /bin/ls --json --function _main
```

### Output Format

```
MachScope - Disassembly

Address Range: 0x100003f40 - 0x100003fa0

0x100003f40    stp     x29, x30, [sp, #-16]!
0x100003f44    mov     x29, sp
0x100003f48    bl      0x100003f80         ; _helper
0x100003f4c    ldp     x29, x30, [sp], #16
0x100003f50    ret                         ; [PAC: return]

Total: 5 instructions (20 bytes)
```

### PAC Annotations

MachScope automatically annotates Pointer Authentication instructions:

```
0x100003f50    retab                       ; [PAC: authenticated return]
0x100003f54    blraaz  x8                  ; [PAC: authenticated call]
```

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | File not found |
| 2 | Invalid Mach-O format |
| 5 | Symbol not found |
| 6 | Invalid address |
| 7 | Section not found |

---

## Check-Permissions Command

Check system permissions and available capabilities.

### Syntax

```bash
machscope check-permissions [options]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--json` | `-j` | Output in JSON format |
| `--verbose` | `-v` | Show detailed information |

### Examples

```bash
# Basic check
machscope check-permissions

# Verbose output
machscope check-permissions --verbose

# JSON output
machscope check-permissions --json
```

### Output

```
MachScope Permission Check

Feature               Status      Notes
------------------------------------------------------------
Static Analysis       ✓ Ready     No special permissions needed
Disassembly           ✓ Ready     No special permissions needed
Debugger              ✗ Denied    Missing debugger entitlement
  → Developer Tools   ✗ Off       Enable in System Settings
  → Entitlement       ✗ No        Run codesign with entitlements

SIP Status: Enabled
  Note: System binaries cannot be debugged with SIP enabled

Capability Level: Analysis (parse + disasm only)

To enable debugging:
  1. Open System Settings > Privacy & Security > Developer Tools
  2. Enable "Terminal" (or add MachScope if installed)
  3. Restart Terminal
  • Sign binary: codesign --force --sign - --entitlements Resources/MachScope.entitlements .build/debug/machscope
```

### Capability Levels

| Level | Features | Exit Code |
|-------|----------|-----------|
| Full | parse + disasm + debug | 0 |
| Analysis | parse + disasm only | 20 |
| Read-Only | parse only | 21 |

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Full capabilities available |
| 20 | Partial capabilities (analysis only) |
| 21 | Minimal capabilities (parse only) |

---

## Debug Command

Attach to and debug a running process.

### Prerequisites

1. Sign MachScope with debugger entitlement
2. Enable Developer Tools in System Settings
3. Target process must have `get-task-allow` entitlement (for non-system binaries)

### Syntax

```bash
machscope debug <pid> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<pid>` | Process ID to attach to |

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--json` | `-j` | Output in JSON format (non-interactive) |

### Setup

```bash
# Sign with debugger entitlement
codesign --force --sign - \
  --entitlements Resources/MachScope.entitlements \
  .build/debug/machscope

# Find a process ID
ps aux | grep MyApp
```

### Interactive Commands

Once attached, use these commands:

| Command | Short | Description |
|---------|-------|-------------|
| `help` | `h` | Show available commands |
| `continue` | `c` | Continue execution |
| `step` | `s` | Single step one instruction |
| `break <addr>` | `b` | Set breakpoint at address |
| `delete <id>` | `d` | Delete breakpoint |
| `info breakpoints` | | List all breakpoints |
| `info registers` | | Show register values |
| `registers` | `regs` | Show all registers |
| `x <addr> [count]` | | Examine memory |
| `disasm [addr] [count]` | `dis` | Disassemble at address |
| `backtrace` | `bt` | Show call stack |
| `detach` | | Detach from process |
| `quit` | `q` | Quit debugger |

### Examples

```bash
# Attach to process
machscope debug 12345

# In debugger:
(machscope) info registers
(machscope) break 0x100003f40
(machscope) continue
(machscope) step
(machscope) x 0x100000000 16
(machscope) backtrace
(machscope) quit
```

### Exit Codes

| Code | Description |
|------|-------------|
| 0 | Normal exit |
| 1 | Process not found |
| 10 | Permission denied (missing entitlement) |
| 11 | SIP protection (target is system binary) |
| 12 | Target lacks get-task-allow |
| 13 | Attach failed |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `NO_COLOR` | Disable colored output (any value) |
| `MACHSCOPE_COLOR` | Override color mode (always/never/auto) |

```bash
# Disable colors
export NO_COLOR=1
machscope parse /bin/ls

# Force colors
export MACHSCOPE_COLOR=always
machscope parse /bin/ls
```

---

## Tips and Tricks

### Pipe to Less with Colors

```bash
machscope parse /bin/ls --color always | less -R
```

### Save Analysis to File

```bash
machscope parse /bin/ls --all --json > analysis.json
```

### Compare Two Binaries

```bash
diff <(machscope parse /bin/ls --json) <(machscope parse /bin/cat --json)
```

### Find App Executable

```bash
# Get executable name from Info.plist
APP="/Applications/Safari.app"
EXEC=$(defaults read "$APP/Contents/Info.plist" CFBundleExecutable)
machscope parse "$APP/Contents/MacOS/$EXEC"
```

### Batch Analysis

```bash
# Analyze all binaries in /bin
for bin in /bin/*; do
  echo "=== $bin ==="
  machscope parse "$bin" --headers 2>/dev/null
done
```
