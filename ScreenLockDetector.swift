//
//  ScreenLockDetector.swift
//  ScreenLockDetector
//
//  Created by Camilo Vega on 26/09/25.
//

import Cocoa
import Foundation
import os.log

// MARK: - Configuration
struct Configuration {
    static let executionDelay: TimeInterval = 2.0
    static let maxRetries = 3
    static let retryInterval: TimeInterval = 5.0

    // Shortcut names
    static let setOnShortcut = "Your Unlock Shortcut"
    static let setOffShortcut = "Your Lock Shortcut"

    // Logging
    static let enableLogging = true
}

// MARK: - Logger
class Logger {
    private static let subsystem = "screen-lock-detector"
    private static let logger = os.Logger(subsystem: subsystem, category: "main")
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func log(_ message: String, type: OSLogType = .default) {
        if Configuration.enableLogging {
            print("\(dateFormatter.string(from: Date())) - \(message)")
        }

        logger.log(level: type, "\(message)")
    }
}

// MARK: - System State Manager
class SystemState {
    private var lastState: String = "unknown"
    private var isExecutingCommand = false
    private let queue = DispatchQueue(label: "screen-lock-detector.state", qos: .background)
    private var lastExecution: Date?

    func processEvent(_ event: String, action: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Avoid duplicate events
            if self.lastState == event {
                Logger.log("[WARN] Duplicate event ignored: \(event)", type: .debug)
                return
            }

            // Avoid rapid executions (debouncing)
            if let lastExec = self.lastExecution,
                Date().timeIntervalSince(lastExec) < 1.0
            {
                Logger.log("[DEBOUNCE] Event too recent, ignoring", type: .debug)
                return
            }

            // Avoid concurrent executions
            if self.isExecutingCommand {
                Logger.log("[BUSY] Command in progress, ignoring...", type: .debug)
                return
            }

            self.isExecutingCommand = true
            self.lastState = event
            self.lastExecution = Date()

            // Configurable delay with async execution
            if Configuration.executionDelay > 0 {
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + Configuration.executionDelay
                ) {
                    action()
                    self.isExecutingCommand = false
                }
            } else {
                action()
                self.isExecutingCommand = false
            }
        }
    }
}

// MARK: - Shortcut Executor
class ShortcutExecutor {
    static func execute(_ shortcutName: String, attempt: Int = 1) {
        let queue = DispatchQueue.global(qos: .utility)

        queue.async {
            autoreleasepool {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                task.arguments = ["run", shortcutName]
                task.qualityOfService = .utility

                // Capture output
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                task.standardOutput = outputPipe
                task.standardError = errorPipe

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 {
                        Logger.log("[OK] Successfully executed: \(shortcutName)", type: .info)
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString =
                            String(data: errorData, encoding: .utf8) ?? "Unknown error"

                        if attempt < Configuration.maxRetries {
                            Logger.log(
                                "[ERROR] Error executing \(shortcutName): \(errorString)",
                                type: .error)
                            Logger.log(
                                "[RETRY] Retrying (attempt \(attempt + 1)/\(Configuration.maxRetries))",
                                type: .info)

                            DispatchQueue.global(qos: .utility).asyncAfter(
                                deadline: .now() + Configuration.retryInterval
                            ) {
                                execute(shortcutName, attempt: attempt + 1)
                            }
                        } else {
                            Logger.log(
                                "[FAIL] Permanent failure after \(Configuration.maxRetries) attempts: \(shortcutName)",
                                type: .error)
                        }
                    }
                } catch {
                    Logger.log(
                        "[CRITICAL] Critical error executing \(shortcutName): \(error.localizedDescription)",
                        type: .fault)
                }
            }
        }
    }
}

// MARK: - Screen Lock Monitor
class ScreenLockMonitor {
    private let systemState = SystemState()
    private let notificationCenter = DistributedNotificationCenter.default()
    private var observers: [NSObjectProtocol] = []

    init() {
        setupSignalHandlers()
        checkInitialState()
        setupObservers()
    }

    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            Logger.log("\n[EXIT] Received SIGINT signal - Stopping monitor...", type: .info)
            Thread.sleep(forTimeInterval: 0.5)
            exit(0)
        }

        signal(SIGTERM) { _ in
            Logger.log("\n[TERM] Received SIGTERM signal - Terminating...", type: .info)
            Thread.sleep(forTimeInterval: 0.5)
            exit(0)
        }
    }

    private func checkInitialState() {
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            let isLocked = dict["CGSSessionScreenIsLocked"] as? Int == 1

            if isLocked {
                Logger.log("[LOCK] Initial state: LOCKED", type: .info)
                systemState.processEvent("locked") {
                    ShortcutExecutor.execute(Configuration.setOffShortcut)
                }
            } else {
                Logger.log("[UNLOCK] Initial state: UNLOCKED", type: .info)
                systemState.processEvent("unlocked") {
                    ShortcutExecutor.execute(Configuration.setOnShortcut)
                }
            }
        } else {
            Logger.log("[WARN] Could not determine initial state", type: .error)
        }
    }

    private func setupObservers() {
        // Observer for screen locked
        let lockObserver = notificationCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: OperationQueue(),
            using: { [weak self] _ in
                Logger.log("[LOCK] Event: Mac LOCKED", type: .info)
                self?.systemState.processEvent("locked") {
                    ShortcutExecutor.execute(Configuration.setOffShortcut)
                }
            }
        )

        // Observer for screen unlocked
        let unlockObserver = notificationCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: OperationQueue(),
            using: { [weak self] _ in
                Logger.log("[UNLOCK] Event: Mac UNLOCKED", type: .info)
                self?.systemState.processEvent("unlocked") {
                    ShortcutExecutor.execute(Configuration.setOnShortcut)
                }
            }
        )

        observers = [lockObserver, unlockObserver]
    }

    func start() {
        Logger.log(String(repeating: "=", count: 50), type: .info)
        Logger.log("[INIT] Screen Lock Detector", type: .info)
        Logger.log(String(repeating: "=", count: 50), type: .info)
        Logger.log("Configuration:", type: .info)
        Logger.log(" - Execution delay: \(Configuration.executionDelay)s", type: .info)
        Logger.log(" - Max retries: \(Configuration.maxRetries)", type: .info)
        Logger.log(" - On shortcut: '\(Configuration.setOnShortcut)'", type: .info)
        Logger.log(" - Off shortcut: '\(Configuration.setOffShortcut)'", type: .info)
        Logger.log(String(repeating: "=", count: 50), type: .info)
        Logger.log("Monitor started. Press Ctrl+C to stop\n", type: .info)

        RunLoop.main.run()
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
    }
}

// MARK: - Entry Point
let monitor = ScreenLockMonitor()
monitor.start()
