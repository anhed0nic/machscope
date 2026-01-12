# Troubleshooting Guide

Common issues and their solutions.

## Build Issues

### Swift Version Error

**Error:**
```
error: package requires Swift version 6.0 or later
```

**Solution:**
Update Xcode to version 16.0 or later:
```bash
xcode-select --install
swift --version  # Should show 6.0+
```

### Module Not Found

**Error:**
```
error: no such module 'MachOKit'
```

**Solution:**
Clean and rebuild:
```bash
swift package clean
swift build
```

### Linking Errors

**Error:**
```
Undefined symbols for architecture arm64
```

**Solution:**
Ensure all targets are built:
```bash
swift build --build-tests
```

---

## Parse Command Issues

### File Not Found

**Error:**
```
Error: File not found: /path/to/binary
```

**Solutions:**
1. Check the path exists:
   ```bash
   ls -la /path/to/binary
   ```

2. Use absolute paths:
   ```bash
   machscope parse "$(pwd)/binary"
   ```

3. For apps, use the executable inside:
   ```bash
   machscope parse /Applications/App.app/Contents/MacOS/App
   ```

### Invalid Magic Number

**Error:**
```
Error: Invalid magic number 0x... at offset 0
```

**Causes:**
- File is not a Mach-O binary
- File is corrupted
- File is a different format (ELF, PE, etc.)

**Solution:**
Verify the file type:
```bash
file /path/to/binary
# Should show: Mach-O 64-bit executable arm64
```

### Architecture Not Found

**Error:**
```
Error: Architecture 'arm64' not found in Fat binary
```

**Solution:**
List available architectures:
```bash
lipo -info /path/to/binary
```

Then specify the correct one:
```bash
machscope parse /path/to/binary --arch x86_64
```

### Permission Denied

**Error:**
```
Error: Error accessing file '/path': Permission denied
```

**Solution:**
Check file permissions:
```bash
ls -la /path/to/binary
```

For system files, you may need to copy first:
```bash
cp /bin/ls ./ls_copy
machscope parse ./ls_copy
```

---

## Disassembly Issues

### Symbol Not Found

**Error:**
```
Error: Symbol '_myFunction' not found
```

**Solutions:**
1. List available functions:
   ```bash
   machscope disasm /path/to/binary --list-functions
   ```

2. Check symbol name (may need underscore prefix):
   ```bash
   machscope disasm /path/to/binary --function _main
   ```

3. Use address instead:
   ```bash
   machscope disasm /path/to/binary --address 0x100003f40
   ```

### Section Not Found

**Error:**
```
Error: Section '__text' not found
```

**Solution:**
List segments and sections:
```bash
machscope parse /path/to/binary --segments
```

### Invalid Address

**Error:**
```
Error: Address 0x... out of range
```

**Solution:**
Check valid address ranges in segments:
```bash
machscope parse /path/to/binary --segments
```

Use an address within `__TEXT`:
```
VM Address:  0x0000000100000000
VM Size:     32.00 KB
```

### No Functions Found

**Output:**
```
No functions found in __TEXT,__text section
```

**Cause:**
The binary may be stripped or use a different symbol format.

**Solutions:**
1. Check if symbols exist:
   ```bash
   machscope parse /path/to/binary --symbols
   ```

2. Disassemble by address instead:
   ```bash
   machscope disasm /path/to/binary --address 0x100003f40
   ```

---

## Debug Command Issues

### Permission Denied (Code 10)

**Error:**
```
Error: Missing debugger entitlement
```

**Solution:**
Sign with entitlements:
```bash
codesign --force --sign - \
  --entitlements Resources/MachScope.entitlements \
  .build/debug/machscope
```

### Developer Tools Disabled

**Error:**
```
Developer Tools not enabled
```

**Solution:**
1. Open **System Settings**
2. Go to **Privacy & Security** > **Developer Tools**
3. Enable **Terminal**
4. Restart Terminal

### SIP Blocking (Code 11)

**Error:**
```
Error: SIP blocks access to '/bin/ls'
```

**Cause:**
System Integrity Protection prevents debugging system binaries.

**Solutions:**
1. Debug non-system binaries (apps in /Applications)
2. Copy to non-protected location:
   ```bash
   cp /bin/ls ./ls_copy
   # Sign with get-task-allow
   codesign --force --sign - --entitlements - ./ls_copy <<EOF
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.get-task-allow</key>
       <true/>
   </dict>
   </plist>
   EOF
   ./ls_copy &
   machscope debug $!
   ```

### Target Lacks get-task-allow (Code 12)

**Error:**
```
Error: Target process lacks get-task-allow entitlement
```

**Cause:**
Production apps don't have debug entitlement.

**Solution:**
Only debug development builds with `get-task-allow`.

### Process Not Found (Code 1)

**Error:**
```
Error: Process not found: 12345
```

**Solutions:**
1. Verify the PID exists:
   ```bash
   ps -p 12345
   ```

2. Find correct PID:
   ```bash
   ps aux | grep MyApp
   pgrep -l MyApp
   ```

### Attach Failed (Code 13)

**Error:**
```
Error: Cannot attach to process: Operation not permitted
```

**Causes:**
- Another debugger is attached (lldb, Xcode)
- Process is a system daemon
- Insufficient permissions

**Solutions:**
1. Detach other debuggers first
2. Check permissions:
   ```bash
   machscope check-permissions
   ```

---

## Output Issues

### No Colors in Output

**Causes:**
- Output is piped/redirected
- NO_COLOR environment variable set
- --color never specified

**Solutions:**
1. Force colors:
   ```bash
   machscope parse /bin/ls --color always
   ```

2. Check environment:
   ```bash
   unset NO_COLOR
   ```

3. Use `less -R` for paging with colors:
   ```bash
   machscope parse /bin/ls --color always | less -R
   ```

### Truncated Output

**Cause:**
Large binaries produce lots of output.

**Solutions:**
1. Limit output:
   ```bash
   machscope parse /bin/ls --headers
   machscope parse /bin/ls --symbols | head -50
   ```

2. Save to file:
   ```bash
   machscope parse /bin/ls --all > output.txt
   ```

3. Use JSON for processing:
   ```bash
   machscope parse /bin/ls --json | jq '.symbols | length'
   ```

### JSON Parse Errors

**Error:**
```
Error: JSON parsing failed
```

**Cause:**
Mixed text and JSON output.

**Solution:**
Ensure only JSON output:
```bash
machscope parse /bin/ls --json 2>/dev/null | jq .
```

---

## Memory Issues

### High Memory Usage

**Cause:**
Loading very large binaries into memory.

**Solutions:**
1. MachScope automatically uses mmap for files > 10MB
2. Parse specific sections:
   ```bash
   machscope parse /path/to/large --headers
   ```

### Crash on Large Files

**Cause:**
Insufficient memory for very large binaries.

**Solution:**
Parse sections individually:
```bash
machscope parse /path/to/large --segments
machscope parse /path/to/large --symbols
```

---

## Check Permissions Issues

### Exit Code 20 or 21

**Meaning:**
- Code 20: Analysis only (can parse + disasm)
- Code 21: Read-only (can only parse)

**This is expected** if debugger entitlements aren't configured.

**To enable full capabilities:**
1. Sign with debugger entitlement
2. Enable Developer Tools
3. Verify:
   ```bash
   machscope check-permissions
   ```

---

## General Tips

### Verbose Errors

Get more information:
```bash
machscope check-permissions --verbose
```

### Debug Build vs Release

Debug builds have more checks:
```bash
swift build          # Debug
swift build -c release  # Faster, fewer checks
```

### Verify Installation

```bash
machscope --version
which machscope  # If installed globally
```

### Clean State

Reset everything:
```bash
swift package clean
rm -rf .build
swift build
```

### Report Bugs

Include:
1. Command you ran
2. Complete error message
3. macOS version: `sw_vers`
4. Swift version: `swift --version`
5. Binary you were analyzing (if shareable)
