# Contributing Guide

Thank you for your interest in contributing to MachScope!

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 16.0 or later
- Swift 6.0 or later
- Git

### Setup Development Environment

```bash
# Clone the repository
git clone https://github.com/your-repo/MachScope.git
cd MachScope

# Build
swift build

# Run tests
swift test

# Run the CLI
swift run machscope --version
```

## Code Style

### Swift Formatting

We use `swift-format` for consistent code style:

```bash
# Check formatting
xcrun swift-format lint -r Sources/ Tests/

# Auto-format
xcrun swift-format -i -r Sources/ Tests/
```

### Conventions

1. **Indentation**: 2 spaces (swift-format default)
2. **Line Length**: 100 characters max
3. **Imports**: Sorted alphabetically
4. **Access Control**: Explicit (`public`, `private`, etc.)

### Swift 6 Concurrency

All types must be `Sendable`:

```swift
// Good
public struct MyType: Sendable {
    let value: Int
}

// Bad - not Sendable
public struct MyType {
    var callback: () -> Void
}
```

### Error Handling

Use domain-specific error types:

```swift
// Good
throw MachOParseError.fileNotFound(path: path)

// Bad
throw NSError(domain: "MyError", code: 1)
```

### Documentation

Document public APIs:

```swift
/// Parses a Mach-O binary from the given path.
///
/// - Parameters:
///   - path: Absolute path to the binary file
///   - architecture: Target architecture for Universal binaries
/// - Returns: Parsed binary representation
/// - Throws: `MachOParseError` if parsing fails
public init(path: String, architecture: CPUType = .arm64) throws
```

## Project Structure

```
Sources/
├── MachOKit/        # Core Mach-O parsing (no dependencies)
├── Disassembler/    # ARM64 decoder (depends on MachOKit)
├── DebuggerCore/    # Process debugging (depends on both)
└── MachScope/       # CLI application (depends on all)

Tests/
├── MachOKitTests/
├── DisassemblerTests/
├── DebuggerCoreTests/
└── IntegrationTests/
```

### Module Guidelines

- **MachOKit**: No external dependencies, pure parsing
- **Disassembler**: Only depends on MachOKit via protocols
- **DebuggerCore**: Can use all modules
- **MachScope**: CLI only, no business logic

## Testing

### Running Tests

```bash
# All tests
swift test

# Specific test target
swift test --filter MachOKitTests

# Specific test
swift test --filter MachOKitTests.HeaderTests/testCPUTypeARM64
```

### Writing Tests

```swift
import XCTest
@testable import MachOKit

final class MyTests: XCTestCase {

    func testSomething() throws {
        // Arrange
        let input = ...

        // Act
        let result = try myFunction(input)

        // Assert
        XCTAssertEqual(result, expected)
    }

    func testError() {
        // Test error cases
        XCTAssertThrowsError(try myFunction(badInput)) { error in
            XCTAssertTrue(error is MachOParseError)
        }
    }
}
```

### Test Fixtures

Test binaries are in `Tests/MachOKitTests/Fixtures/`:

```bash
Tests/MachOKitTests/Fixtures/
├── simple_arm64          # Basic ARM64 executable
├── fat_binary            # Universal binary
├── malformed/
│   ├── truncated         # Truncated header
│   └── invalid_magic     # Wrong magic number
└── README.md             # Fixture creation instructions
```

### Creating New Fixtures

```bash
# Create a simple test binary
echo 'int main() { return 0; }' > test.c
clang -arch arm64 -o simple_arm64 test.c

# Create Universal binary
clang -arch arm64 -o arm64_bin test.c
clang -arch x86_64 -o x64_bin test.c
lipo -create arm64_bin x64_bin -output fat_binary
```

## Pull Request Process

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/bug-description
```

### 2. Make Changes

- Write code following style guidelines
- Add tests for new functionality
- Update documentation if needed

### 3. Test Your Changes

```bash
# Build
swift build

# Run all tests
swift test

# Format code
xcrun swift-format -i -r Sources/ Tests/
```

### 4. Commit

```bash
git add .
git commit -m "Add feature X

- Detailed description
- Of changes made

Co-Authored-By: Your Name <email@example.com>"
```

### 5. Push and Create PR

```bash
git push origin feature/my-feature
```

Then create a Pull Request on GitHub.

### PR Guidelines

- Clear title describing the change
- Description of what and why
- Link to related issues
- Tests passing
- Documentation updated

## Types of Contributions

### Bug Fixes

1. Check existing issues
2. Create issue if new bug
3. Fork, fix, test, PR

### New Features

1. Open issue to discuss
2. Get approval on approach
3. Implement with tests
4. Update docs
5. PR

### Documentation

- Fix typos and errors
- Add examples
- Improve clarity
- Translate

### Performance

- Profile before optimizing
- Include benchmarks
- Document improvements

## Architecture Guidelines

### Adding New Load Commands

1. Add case to `LoadCommandType` enum
2. Create payload struct if needed
3. Add parsing in `LoadCommand.parseAll`
4. Add tests

```swift
// In LoadCommand.swift
case myNewCommand = 0x99

// Parsing
case .myNewCommand:
    let data = try parseMyNewCommand(from: reader, at: offset, size: Int(size))
    return LoadCommand(type: type, size: size, payload: .myNewCommand(data))
```

### Adding New Disassembler Instructions

1. Identify instruction encoding pattern
2. Add to appropriate decoder file
3. Add formatting
4. Add tests

### Adding New CLI Commands

1. Create `NewCommand.swift` in `Commands/`
2. Add case in `main.swift`
3. Add help text
4. Add tests

## Code Review

### What We Look For

- Correctness
- Tests coverage
- Performance implications
- API design
- Documentation
- Swift idioms

### Feedback

- Be constructive
- Explain reasoning
- Suggest alternatives
- Be respectful

## Community

### Getting Help

- GitHub Issues for bugs/features
- GitHub Discussions for questions
- Code comments for clarification

### Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Focus on constructive feedback
- No harassment or discrimination

## Release Process

1. Update version in `main.swift`
2. Update CLAUDE.md
3. Run full test suite
4. Create git tag
5. Build release binary
6. Create GitHub release

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT).

---

Thank you for contributing to MachScope!
