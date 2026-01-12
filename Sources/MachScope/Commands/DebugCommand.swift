// DebugCommand.swift
// MachScope
//
// Debug command implementation

import DebuggerCore
import Foundation

/// Debug command - attach to and debug a running process
public struct DebugCommand: Sendable {

  /// Execute the debug command
  /// - Parameter args: Parsed arguments
  /// - Returns: Exit code
  public static func execute(args: ParsedArguments) -> Int32 {
    // Get PID from arguments
    guard let pidString = args.positional.first,
      let pid = Int32(pidString)
    else {
      printError("Usage: machscope debug <pid>")
      printError("  Example: machscope debug 12345")
      return 1
    }

    // Check if JSON output requested
    let jsonOutput = args.hasFlag("json") || args.hasFlag("j")

    // Check permissions first
    let permissionChecker = PermissionChecker()
    guard permissionChecker.canDebug else {
      if jsonOutput {
        printJSON(makePermissionErrorJSON(permissionChecker))
      } else {
        printPermissionError(permissionChecker)
      }
      return permissionChecker.exitCode
    }

    // Create debugger and attach
    let debugger = Debugger()

    do {
      try debugger.attach(to: pid)

      if jsonOutput {
        // Non-interactive mode for JSON - just print attachment status
        let output = makeAttachJSON(debugger)
        printJSON(output)
      } else {
        // Interactive mode
        runInteractiveMode(debugger: debugger)
      }

      try debugger.detach()
      return 0

    } catch let error as DebuggerError {
      if jsonOutput {
        printJSON(makeErrorJSON(error))
      } else {
        printError("Error: \(error.description)")
        printGuidance(for: error)
      }
      return error.exitCode

    } catch {
      if jsonOutput {
        printJSON(makeErrorJSON(error))
      } else {
        printError("Error: \(error.localizedDescription)")
      }
      return 1
    }
  }

  // MARK: - Interactive Mode

  private static func runInteractiveMode(debugger: Debugger) {
    print("MachScope Debugger")
    print("")

    if let pid = debugger.pid, let name = debugger.processName {
      print("Attached to process \(pid) (\(name))")
    } else if let pid = debugger.pid {
      print("Attached to process \(pid)")
    }
    print("Stopped at entry point")
    print("")
    print("Type 'help' for available commands, 'quit' to exit.")
    print("")

    var running = true

    while running {
      print("(machscope) ", terminator: "")
      fflush(stdout)

      guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
        !input.isEmpty
      else {
        continue
      }

      let parts = input.components(separatedBy: .whitespaces)
      let command = parts[0].lowercased()
      let commandArgs = Array(parts.dropFirst())

      switch command {
      case "help", "h":
        printHelp()

      case "continue", "c":
        doContinue(debugger: debugger)

      case "step", "s":
        doStep(debugger: debugger)

      case "break", "b":
        doBreak(debugger: debugger, args: commandArgs)

      case "delete", "d":
        doDelete(debugger: debugger, args: commandArgs)

      case "info":
        doInfo(debugger: debugger, args: commandArgs)

      case "x":
        doExamine(debugger: debugger, args: commandArgs)

      case "disasm", "dis":
        doDisasm(debugger: debugger, args: commandArgs)

      case "print", "p":
        doPrint(debugger: debugger, args: commandArgs)

      case "registers", "regs", "ir":
        doRegisters(debugger: debugger)

      case "backtrace", "bt":
        doBacktrace(debugger: debugger)

      case "detach":
        print("Detaching from process...")
        running = false

      case "quit", "q":
        print("Quitting...")
        running = false

      default:
        print("Unknown command: '\(command)'. Type 'help' for available commands.")
      }
    }
  }

  // MARK: - Command Implementations

  private static func printHelp() {
    print(
      """
      Available commands:

      Execution:
        continue (c)              Continue execution
        step (s)                  Single step one instruction

      Breakpoints:
        break <addr/symbol> (b)   Set breakpoint at address or symbol
        delete <id> (d)           Delete breakpoint by ID
        info breakpoints (ib)     List all breakpoints

      Inspection:
        info registers (ir)       Show all registers
        registers (regs)          Show all registers
        x/<n><f> <addr>           Examine memory (n=count, f=format)
        disasm [addr] [count]     Disassemble at address
        print <expr> (p)          Print expression value
        backtrace (bt)            Show call stack

      Control:
        detach                    Detach from process
        quit (q)                  Exit debugger

      Format specifiers for 'x':
        b = bytes, h = halfwords (16-bit), w = words (32-bit), g = giant (64-bit)

      Examples:
        break 0x100003f40
        x/8w 0x100003f40
        disasm 0x100003f40 20
      """)
  }

  private static func doContinue(debugger: Debugger) {
    do {
      try debugger.continueExecution()
      print("Continuing...")
      // In a real debugger, we'd wait for an event here
    } catch {
      print("Error: \(error)")
    }
  }

  private static func doStep(debugger: Debugger) {
    #if arch(arm64)
      do {
        try debugger.step()
        if let pc = try? debugger.programCounter() {
          print("Stepped to 0x\(String(pc, radix: 16))")
        }
      } catch {
        print("Error: \(error)")
      }
    #else
      print("Step not supported on this architecture")
    #endif
  }

  private static func doBreak(debugger: Debugger, args: [String]) {
    guard let addrStr = args.first else {
      print("Usage: break <address>")
      print("  Example: break 0x100003f40")
      return
    }

    // Parse address (support 0x prefix)
    let cleanAddr =
      addrStr.hasPrefix("0x")
      ? String(addrStr.dropFirst(2))
      : addrStr

    guard let address = UInt64(cleanAddr, radix: 16) else {
      print("Invalid address: \(addrStr)")
      return
    }

    do {
      let id = try debugger.setBreakpoint(at: address)
      print("Breakpoint \(id) set at 0x\(String(address, radix: 16))")
    } catch {
      print("Error setting breakpoint: \(error)")
    }
  }

  private static func doDelete(debugger: Debugger, args: [String]) {
    guard let idStr = args.first, let id = Int(idStr) else {
      print("Usage: delete <breakpoint-id>")
      return
    }

    do {
      try debugger.removeBreakpoint(id: id)
      print("Deleted breakpoint \(id)")
    } catch {
      print("Error: \(error)")
    }
  }

  private static func doInfo(debugger: Debugger, args: [String]) {
    guard let subcommand = args.first?.lowercased() else {
      print("Usage: info <subcommand>")
      print("  Subcommands: breakpoints (ib), registers (ir)")
      return
    }

    switch subcommand {
    case "breakpoints", "b":
      let bps = debugger.breakpoints
      if bps.isEmpty {
        print("No breakpoints set.")
      } else {
        print("Num  Type       Address            What")
        for bp in bps {
          let enabled = bp.isEnabled ? "breakpoint" : "disabled  "
          let symbol = bp.symbol.map { " <\($0)>" } ?? ""
          print(
            "\(bp.id)    \(enabled) 0x\(String(bp.address, radix: 16).leftPadding(toLength: 16, withPad: "0"))\(symbol)"
          )
          if bp.hitCount > 0 {
            print("       breakpoint already hit \(bp.hitCount) time(s)")
          }
        }
      }

    case "registers", "r":
      doRegisters(debugger: debugger)

    default:
      print("Unknown info subcommand: \(subcommand)")
    }
  }

  private static func doExamine(debugger: Debugger, args: [String]) {
    // Parse x/<n><f> <addr> format
    guard !args.isEmpty else {
      print("Usage: x/<count><format> <address>")
      print("  Example: x/8w 0x100003f40")
      return
    }

    var count = 4
    var format: Character = "w"
    var addrStr: String

    if args.count == 1 {
      addrStr = args[0]
    } else {
      // First arg might be /<n><f>
      let spec = args[0]
      addrStr = args[1]

      if spec.hasPrefix("/") {
        let specPart = String(spec.dropFirst())
        // Parse count and format
        var numStr = ""
        for char in specPart {
          if char.isNumber {
            numStr.append(char)
          } else {
            format = char
            break
          }
        }
        if let n = Int(numStr) {
          count = n
        }
      }
    }

    // Parse address
    let cleanAddr =
      addrStr.hasPrefix("0x")
      ? String(addrStr.dropFirst(2))
      : addrStr

    guard let address = UInt64(cleanAddr, radix: 16) else {
      print("Invalid address: \(addrStr)")
      return
    }

    do {
      let output = try debugger.examineMemory(at: address, count: count, format: format)
      print(output)
    } catch {
      print("Error reading memory: \(error)")
    }
  }

  private static func doDisasm(debugger: Debugger, args: [String]) {
    #if arch(arm64)
      do {
        let address: UInt64
        let count: Int

        if args.isEmpty {
          // Disassemble at current PC
          address = try debugger.programCounter()
          count = 10
        } else {
          let addrStr = args[0]
          let cleanAddr =
            addrStr.hasPrefix("0x")
            ? String(addrStr.dropFirst(2))
            : addrStr

          guard let addr = UInt64(cleanAddr, radix: 16) else {
            print("Invalid address: \(addrStr)")
            return
          }
          address = addr
          count = args.count > 1 ? (Int(args[1]) ?? 10) : 10
        }

        let output = try debugger.disassemble(at: address, count: count)
        print(output)
      } catch {
        print("Error: \(error)")
      }
    #else
      print("Disassembly not supported on this architecture")
    #endif
  }

  private static func doPrint(debugger: Debugger, args: [String]) {
    guard let expr = args.first else {
      print("Usage: print <expression>")
      return
    }

    // For now, just support reading addresses
    let cleanAddr =
      expr.hasPrefix("0x")
      ? String(expr.dropFirst(2))
      : expr

    if let address = UInt64(cleanAddr, radix: 16) {
      do {
        let data = try debugger.readMemory(at: address, size: 8)
        let value = data.withUnsafeBytes { ptr in
          ptr.load(as: UInt64.self)
        }
        print("0x\(String(value, radix: 16))")
      } catch {
        print("Error reading memory: \(error)")
      }
    } else {
      print("Cannot evaluate expression: \(expr)")
    }
  }

  private static func doRegisters(debugger: Debugger) {
    #if arch(arm64)
      do {
        let regs = try debugger.registers()
        print(regs.description)
      } catch {
        print("Error reading registers: \(error)")
      }
    #else
      print("Register reading not supported on this architecture")
    #endif
  }

  private static func doBacktrace(debugger: Debugger) {
    #if arch(arm64)
      do {
        let regs = try debugger.registers()

        print("Thread backtrace:")
        print("#0  0x\(String(regs.pc, radix: 16).leftPadding(toLength: 16, withPad: "0"))")

        // Simple frame walking (follow fp chain)
        var fp = regs.fp
        var frameNum = 1

        while fp != 0 && frameNum < 20 {
          do {
            let lr = try debugger.readMemory(at: fp + 8, size: 8).withUnsafeBytes { ptr in
              ptr.load(as: UInt64.self)
            }
            let nextFp = try debugger.readMemory(at: fp, size: 8).withUnsafeBytes { ptr in
              ptr.load(as: UInt64.self)
            }

            print(
              "#\(frameNum)  0x\(String(lr, radix: 16).leftPadding(toLength: 16, withPad: "0"))")

            fp = nextFp
            frameNum += 1
          } catch {
            break
          }
        }
      } catch {
        print("Error reading backtrace: \(error)")
      }
    #else
      print("Backtrace not supported on this architecture")
    #endif
  }

  // MARK: - Output Helpers

  private static func printError(_ message: String) {
    fputs("\(message)\n", stderr)
  }

  private static func printPermissionError(_ checker: PermissionChecker) {
    printError("Error: Cannot attach to process - insufficient permissions")
    printError("")
    print(checker.guidance)
  }

  private static func printGuidance(for error: DebuggerError) {
    switch error {
    case .permissionDenied(_, let guidance),
      .missingDebuggerEntitlement(let guidance),
      .developerToolsNotEnabled(let guidance),
      .sipBlocking(_, let guidance):
      print("")
      print(guidance)
    default:
      break
    }
  }

  private static func printJSON(_ dict: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
      let string = String(data: data, encoding: .utf8)
    {
      print(string)
    }
  }

  // MARK: - JSON Output

  private static func makeAttachJSON(_ debugger: Debugger) -> [String: Any] {
    return [
      "attached": true,
      "pid": debugger.pid ?? 0,
      "processName": debugger.processName ?? "",
      "state": "stopped",
    ]
  }

  private static func makePermissionErrorJSON(_ checker: PermissionChecker) -> [String: Any] {
    let status = checker.status
    return [
      "error": [
        "code": "PERMISSION_DENIED",
        "message": "Cannot attach to process: permission denied",
        "details": [
          "developerTools": status.developerToolsEnabled,
          "debuggerEntitlement": status.debuggerEntitlement,
          "sipEnabled": status.sipEnabled,
        ],
        "resolution": [
          "Enable Developer Tools in System Settings",
          "Sign binary with debugger entitlement",
        ],
      ]
    ]
  }

  private static func makeErrorJSON(_ error: DebuggerError) -> [String: Any] {
    return [
      "error": [
        "code": errorCode(for: error),
        "message": error.description,
        "exitCode": error.exitCode,
      ]
    ]
  }

  private static func makeErrorJSON(_ error: Error) -> [String: Any] {
    return [
      "error": [
        "code": "UNKNOWN_ERROR",
        "message": error.localizedDescription,
      ]
    ]
  }

  private static func errorCode(for error: DebuggerError) -> String {
    switch error {
    case .processNotFound: return "PROCESS_NOT_FOUND"
    case .permissionDenied: return "PERMISSION_DENIED"
    case .missingDebuggerEntitlement: return "MISSING_ENTITLEMENT"
    case .developerToolsNotEnabled: return "DEVELOPER_TOOLS_DISABLED"
    case .sipBlocking: return "SIP_BLOCKING"
    case .targetLacksTaskAllow: return "TARGET_LACKS_TASK_ALLOW"
    case .attachFailed: return "ATTACH_FAILED"
    case .notAttached: return "NOT_ATTACHED"
    default: return "DEBUGGER_ERROR"
    }
  }
}

// MARK: - String Extension

extension String {
  fileprivate func leftPadding(toLength length: Int, withPad pad: String) -> String {
    if self.count >= length {
      return self
    }
    let padding = String(repeating: pad, count: length - self.count)
    return padding + self
  }
}
