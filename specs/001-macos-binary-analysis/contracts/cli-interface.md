# CLI Interface Contract: MachScope

**Feature Branch**: `001-macos-binary-analysis`
**Created**: 2026-01-12

## Overview

MachScope provides a command-line interface with four primary subcommands. This document specifies the exact interface contract including arguments, options, output formats, and exit codes.

---

## Global Options

These options are available on all commands:

| Option | Short | Type | Description |
|--------|-------|------|-------------|
| `--help` | `-h` | flag | Show help for command |
| `--version` | `-v` | flag | Show version information |
| `--json` | `-j` | flag | Output in JSON format |
| `--quiet` | `-q` | flag | Suppress non-essential output |
| `--color` | | enum | Color output: `auto`, `always`, `never` |

---

## Commands

### 1. `machscope parse`

Parse and display Mach-O binary structure.

**Usage**:
```
machscope parse <binary> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `binary` | Yes | Path to Mach-O binary file |

**Options**:

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--arch` | `-a` | string | `arm64` | Architecture for Fat binaries |
| `--segments` | `-s` | flag | true | Show segments and sections |
| `--symbols` | | flag | false | Include symbol table |
| `--strings` | | flag | false | Extract strings from binary |
| `--signatures` | | flag | false | Show code signature details |
| `--entitlements` | `-e` | flag | false | Show entitlements |
| `--load-commands` | `-l` | flag | true | Show load commands |
| `--headers-only` | | flag | false | Only show header info |

**Output Format (Text)**:
```
MachScope - Binary Analysis Tool

File: /path/to/binary
Type: Mach-O 64-bit executable (arm64)
Size: 48,234 bytes

=== Header ===
Magic:       0xfeedfacf (64-bit)
CPU Type:    ARM64
CPU Subtype: ALL
File Type:   EXECUTE
Flags:       PIE TWOLEVEL DYLDLINK

=== Load Commands (25) ===
 #  Type              Size   Details
 0  LC_SEGMENT_64     472    __PAGEZERO
 1  LC_SEGMENT_64     632    __TEXT (0x100000000 - 0x100004000)
 2  LC_SEGMENT_64     312    __DATA_CONST
...

=== Segments ===
__TEXT (0x100000000, 16384 bytes, r-x)
  __text         0x100003f40  1234 bytes  code
  __stubs        0x1000043a4   120 bytes  symbol stubs
  __cstring      0x10000441c   456 bytes  C strings
...

=== Symbols (128 total) ===
0x100003f40 T _main
0x100003fa0 T _helper_function
...
```

**Output Format (JSON)**:
```json
{
  "path": "/path/to/binary",
  "type": "macho64",
  "architecture": "arm64",
  "fileSize": 48234,
  "header": {
    "magic": "0xfeedfacf",
    "cpuType": "arm64",
    "cpuSubtype": "all",
    "fileType": "execute",
    "numberOfCommands": 25,
    "sizeOfCommands": 2776,
    "flags": ["pie", "twolevel", "dyldlink"]
  },
  "loadCommands": [...],
  "segments": [...],
  "symbols": [...],
  "codeSignature": {...}
}
```

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | File not found |
| 2 | Invalid Mach-O format |
| 3 | Unsupported architecture |
| 4 | Parse error (corrupted binary) |

---

### 2. `machscope disasm`

Disassemble ARM64 code from binary.

**Usage**:
```
machscope disasm <binary> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `binary` | Yes | Path to Mach-O binary file |

**Options**:

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--function` | `-f` | string | | Disassemble specific function |
| `--address` | `-a` | hex | | Start address for disassembly |
| `--length` | `-l` | int | 100 | Number of instructions |
| `--section` | | string | `__text` | Section to disassemble |
| `--show-bytes` | `-b` | flag | false | Show raw instruction bytes |
| `--show-address` | | flag | true | Show instruction addresses |
| `--annotate-pac` | | flag | true | Annotate PAC instructions |
| `--annotate-swift` | | flag | true | Annotate Swift patterns |
| `--demangle` | | flag | true | Demangle Swift symbols |

**Output Format (Text)**:
```
MachScope - Disassembly

Function: _main (0x100003f40 - 0x100003fa0)

0x100003f40:  stp    x29, x30, [sp, #-16]!
0x100003f44:  mov    x29, sp
0x100003f48:  sub    sp, sp, #32
0x100003f4c:  str    w0, [sp, #12]
0x100003f50:  str    x1, [sp]
0x100003f54:  bl     _helper_function      ; 0x100003fa0
0x100003f58:  mov    w0, #0
0x100003f5c:  ldp    x29, x30, [sp], #16
0x100003f60:  ret
              ; [PAC] Authenticated return via x30
```

**Output Format (JSON)**:
```json
{
  "function": "_main",
  "startAddress": "0x100003f40",
  "endAddress": "0x100003fa0",
  "instructions": [
    {
      "address": "0x100003f40",
      "encoding": "0xa9bf7bfd",
      "mnemonic": "stp",
      "operands": "x29, x30, [sp, #-16]!",
      "category": "loadStore"
    },
    {
      "address": "0x100003f54",
      "encoding": "0x94000013",
      "mnemonic": "bl",
      "operands": "_helper_function",
      "targetAddress": "0x100003fa0",
      "targetSymbol": "_helper_function",
      "category": "branch"
    }
  ]
}
```

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | File not found |
| 2 | Invalid Mach-O format |
| 5 | Function not found |
| 6 | Invalid address |
| 7 | Section not found |

---

### 3. `machscope debug`

Attach to and debug a running process.

**Usage**:
```
machscope debug <target> [options]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `target` | Yes | Process ID or path to executable |

**Options**:

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--pid` | `-p` | int | | Attach by PID |
| `--args` | | string[] | | Arguments when launching |
| `--no-attach` | | flag | false | Launch but don't stop |

**Interactive Commands** (when attached):

| Command | Alias | Description |
|---------|-------|-------------|
| `continue` | `c` | Continue execution |
| `step` | `s` | Single step |
| `next` | `n` | Step over |
| `break <addr/symbol>` | `b` | Set breakpoint |
| `delete <id>` | `d` | Delete breakpoint |
| `info breakpoints` | `ib` | List breakpoints |
| `info registers` | `ir` | Show registers |
| `x/<n><f> <addr>` | | Examine memory |
| `print <expr>` | `p` | Print expression |
| `disasm [addr]` | | Disassemble at address |
| `backtrace` | `bt` | Show call stack |
| `detach` | | Detach from process |
| `quit` | `q` | Exit debugger |

**Output Format (Text)**:
```
MachScope Debugger

Attached to process 12345 (MyApp)
Stopped at: 0x100003f40 (_main)

(machscope) info registers
x0  = 0x0000000000000001
x1  = 0x000000016fdff400
x2  = 0x0000000000000000
...
sp  = 0x000000016fdff3e0
pc  = 0x0000000100003f40
cpsr = 0x60001000 [nZCv]

(machscope) break _helper_function
Breakpoint 1 at 0x100003fa0 (_helper_function)

(machscope) continue
Breakpoint 1 hit at 0x100003fa0 (_helper_function)
```

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | Normal exit |
| 1 | Process not found |
| 10 | Permission denied (missing entitlement) |
| 11 | SIP protection (target is system binary) |
| 12 | Target lacks get-task-allow |
| 13 | Attach failed |

---

### 4. `machscope check-permissions`

Verify required permissions and entitlements.

**Usage**:
```
machscope check-permissions [options]
```

**Options**:

| Option | Short | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--verbose` | `-v` | flag | false | Show detailed info |

**Output Format (Text)**:
```
MachScope Permission Check

Feature              Status    Notes
───────────────────  ────────  ─────────────────────────────
Static Analysis      ✓ Ready   No special permissions needed
Disassembly          ✓ Ready   No special permissions needed
Debugger             ✗ Denied  Missing debugger entitlement
  → Developer Tools  ✗ Off     Enable in System Settings

To enable debugging:
  1. Open System Settings > Privacy & Security > Developer Tools
  2. Enable "Terminal" (or add MachScope if installed)
  3. Restart Terminal

SIP Status: Enabled
  Note: System binaries cannot be debugged with SIP enabled

Capability Level: Analysis (parse + disasm only)
```

**Output Format (JSON)**:
```json
{
  "capabilities": {
    "staticAnalysis": true,
    "disassembly": true,
    "debugging": false
  },
  "permissions": {
    "developerTools": false,
    "debuggerEntitlement": false,
    "sipEnabled": true
  },
  "capabilityLevel": "analysis",
  "guidance": {
    "developerTools": {
      "path": "System Settings > Privacy & Security > Developer Tools",
      "deepLink": "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools"
    }
  }
}
```

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | Full capabilities available |
| 20 | Partial capabilities (analysis only) |
| 21 | Minimal capabilities (parse only) |

---

## Error Messages

All error messages follow a consistent format:

**Text Format**:
```
Error: <brief description>

<detailed explanation>

To resolve:
  <actionable steps>
```

**JSON Format**:
```json
{
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "Cannot attach to process: permission denied",
    "details": "Target process does not have get-task-allow entitlement",
    "resolution": [
      "Build target with CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES",
      "Or run machscope as root"
    ]
  }
}
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MACHSCOPE_COLOR` | Override color setting | `auto` |
| `MACHSCOPE_PAGER` | Pager for long output | `less` |
| `NO_COLOR` | Disable colors (standard) | unset |

---

## Version Information

```
machscope --version
```

Output:
```
machscope 1.0.0
Built with Swift 6.2.3
Platform: arm64-apple-macosx26.0
```

---

**Document Version**: 1.0
**Last Updated**: 2026-01-12
