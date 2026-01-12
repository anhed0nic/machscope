# Test Fixtures

This directory contains test binaries for MachOKit tests.

## Fixture Files

| File | Description | How to Create |
|------|-------------|---------------|
| `simple_arm64` | Basic ARM64 executable | See below |
| `fat_binary` | Universal binary (arm64 + x86_64) | See below |
| `signed_binary` | Code-signed binary with entitlements | See below |
| `malformed/truncated` | Truncated binary for error handling tests | See below |
| `malformed/invalid_magic` | Invalid magic number | See below |

## Creating Fixtures

### simple_arm64

```bash
cat > /tmp/test.c << 'EOF'
int helper(int x) { return x * 2; }
int main(int argc, char **argv) { return helper(argc); }
EOF

clang -arch arm64 -o Tests/MachOKitTests/Fixtures/simple_arm64 /tmp/test.c
```

### fat_binary

```bash
clang -arch arm64 -arch x86_64 -o Tests/MachOKitTests/Fixtures/fat_binary /tmp/test.c
```

### signed_binary

```bash
cp Tests/MachOKitTests/Fixtures/simple_arm64 Tests/MachOKitTests/Fixtures/signed_binary
codesign --force --sign - --entitlements Resources/MachScope.entitlements \
    Tests/MachOKitTests/Fixtures/signed_binary
```

### malformed/truncated

```bash
head -c 16 Tests/MachOKitTests/Fixtures/simple_arm64 > Tests/MachOKitTests/Fixtures/malformed/truncated
```

### malformed/invalid_magic

```bash
echo -n "XXXX" > Tests/MachOKitTests/Fixtures/malformed/invalid_magic
```

## Notes

- Fixtures are committed to the repository for reproducible testing
- Do not use system binaries in tests (they may change between macOS versions)
- All fixtures target arm64 architecture
