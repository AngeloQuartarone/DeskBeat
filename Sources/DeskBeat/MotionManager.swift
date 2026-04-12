import Foundation
import IOKit.hid

// Struttura interna per gestire la fisica di ogni singolo sensore separatamente
private class DeviceState {
    var gravityX: Double = 0
    var gravityZ: Double = 0
    var prevLinearX: Double = 0
    var prevLinearZ: Double = 0
    var isFirstReport: Bool = true
    var isCollecting: Bool = false
    var collectionStartTime: TimeInterval = 0
    var peakJerkX: Double = 0
    var peakJerkZ: Double = 0
    var lastTap: TimeInterval = 0
    let buffer: UnsafeMutablePointer<UInt8>

    init() {
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    }
    
    deinit {
        buffer.deallocate()
    }
}

final class MotionManager: ObservableObject {
    @Published var isMonitoring: Bool = false {
        didSet {
            if isMonitoring {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var playInBackground: Bool = false
    @Published var isInverted: Bool = UserDefaults.standard.bool(forKey: "isInverted") {
        didSet { UserDefaults.standard.set(isInverted, forKey: "isInverted") }
    }
    @Published var sensitivityLevel: Int = UserDefaults.standard.integer(forKey: "sensitivityLevel") == 0 ? 1 : UserDefaults.standard.integer(forKey: "sensitivityLevel") {
        didSet { UserDefaults.standard.set(sensitivityLevel, forKey: "sensitivityLevel") }
    }
    @Published var selectedKit: String = UserDefaults.standard.string(forKey: "selectedKit") ?? "Classic" {
        didSet { UserDefaults.standard.set(selectedKit, forKey: "selectedKit") }
    }
    @Published var standardSideSound: String = UserDefaults.standard.string(forKey: "standardSideSound") ?? "snare" {
        didSet { UserDefaults.standard.set(standardSideSound, forKey: "standardSideSound") }
    }
    @Published var standardTopSound: String = UserDefaults.standard.string(forKey: "standardTopSound") ?? "kick" {
        didSet { UserDefaults.standard.set(standardTopSound, forKey: "standardTopSound") }
    }
    @Published var isShowingSettings: Bool = false
    
    var onTapDetected: ((String, String) -> Void)?

    private var hidManager: IOHIDManager?
    private var deviceStates: [IOHIDDevice: DeviceState] = [:]
    private var isHardwareActive: Bool = false
    
    private let lockoutDuration: TimeInterval = 0.11
    private let collectionWindowDuration: TimeInterval = 0.015

    static let shared = MotionManager()

    private init() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = hidManager else { return }
        
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 3] as CFDictionary)
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            let m = Unmanaged<MotionManager>.fromOpaque(context!).takeUnretainedValue()
            let state = DeviceState()
            m.deviceStates[device] = state
            
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
            print("🎯 [MotionManager] Agganciato sensore: \(name)")

            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            
            let contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(state).toOpaque())
            
            IOHIDDeviceRegisterInputReportCallback(device, state.buffer, 256, { context, result, sender, type, reportId, report, length in
                let state = Unmanaged<DeviceState>.fromOpaque(context!).takeUnretainedValue()
                MotionManager.shared.process(report, for: state)
            }, contextPtr)
            
        }, selfPtr)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // Inizialmente mettiamo i driver in standby per risparmiare batteria
        sleepSPUDrivers()
    }

    func startMonitoring() {
        if isHardwareActive { return }
        isHardwareActive = true
        wakeSPUDrivers()
        print("🚀 [MotionManager] Monitoraggio riattivato (Hardware Wake)")
    }

    func stopMonitoring() {
        if !isHardwareActive { return }
        isHardwareActive = false
        sleepSPUDrivers()
        print("💤 [MotionManager] Monitoraggio sospeso (Hardware Sleep)")
    }

    private func process(_ report: UnsafePointer<UInt8>, for state: DeviceState) {
        guard isHardwareActive else { return }
        
        let xRaw = Int32(bitPattern: (UInt32(report[9])  << 24) | (UInt32(report[8])  << 16) | (UInt32(report[7])  << 8) | UInt32(report[6]))
        let zRaw = Int32(bitPattern: (UInt32(report[17]) << 24) | (UInt32(report[16]) << 16) | (UInt32(report[15]) << 8) | UInt32(report[14]))
        let x = Double(xRaw) / 65536.0
        let z = Double(zRaw) / 65536.0

        if state.isFirstReport {
            state.gravityX = x
            state.gravityZ = z
            state.isFirstReport = false
            return
        }

        state.gravityX = (x * 0.1) + (state.gravityX * 0.9)
        state.gravityZ = (z * 0.1) + (state.gravityZ * 0.9)
        
        let linearX = x - state.gravityX
        let linearZ = z - state.gravityZ
        let jerkX = linearX - state.prevLinearX
        let jerkZ = linearZ - state.prevLinearZ
        state.prevLinearX = linearX
        state.prevLinearZ = linearZ

        let threshold: Double
        switch sensitivityLevel {
        case 1: threshold = 0.018  // Molto Sordo
        case 2: threshold = 0.016  // Sordo
        case 3: threshold = 0.014  // Medio-Sordo
        case 4: threshold = 0.012  // Sensibile
        case 5: threshold = 0.010  // Molto Sensibile
        default: threshold = 0.014
        }
        
        let now = ProcessInfo.processInfo.systemUptime

        if state.isCollecting {
            if abs(jerkX) > abs(state.peakJerkX) { state.peakJerkX = jerkX }
            if abs(jerkZ) > abs(state.peakJerkZ) { state.peakJerkZ = jerkZ }
            if (now - state.collectionStartTime) >= collectionWindowDuration { 
                fireTap(for: state, at: now) 
            }
            return
        }

        guard (now - state.lastTap) > lockoutDuration else { return }
        
        if max(abs(jerkX), abs(jerkZ)) > threshold {
            state.isCollecting = true
            state.collectionStartTime = now
            state.peakJerkX = jerkX
            state.peakJerkZ = jerkZ
        }
    }

    private func fireTap(for state: DeviceState, at now: TimeInterval) {
        state.isCollecting = false
        state.lastTap = now
        
        let xMagnitude = abs(state.peakJerkX)
        let zMagnitude = abs(state.peakJerkZ)
        let isSideTap = xMagnitude > (zMagnitude * 0.35)
        
        let rawTapType = isSideTap ? "SIDE" : "TOP"
        let side = isSideTap ? "LEFT" : "RIGHT"
        
        DispatchQueue.main.async { 
            self.onTapDetected?(side, rawTapType) 
        }
    }

    private func wakeSPUDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        while true {
            let svc = IOIteratorNext(iterator)
            if svc == 0 { break }
            var n: Int32 = 1
            let cfState = CFNumberCreate(nil, .sInt32Type, &n)
            var interval: Int32 = 10000 
            let cfInterval = CFNumberCreate(nil, .sInt32Type, &interval)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, cfState!)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState" as CFString, cfState!)
            IORegistryEntrySetCFProperty(svc, "ReportInterval" as CFString, cfInterval!)
            IOObjectRelease(svc)
        }
        print("⚡ [MotionManager] Sensori Apple SPU risvegliati (100Hz)")
    }

    private func sleepSPUDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        while true {
            let svc = IOIteratorNext(iterator)
            if svc == 0 { break }
            var n: Int32 = 0 // Spento
            let cfState = CFNumberCreate(nil, .sInt32Type, &n)
            var interval: Int32 = 1000000 // Risparmio massimo (1 report al secondo se attivo)
            let cfInterval = CFNumberCreate(nil, .sInt32Type, &interval)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, cfState!)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState" as CFString, cfState!)
            IORegistryEntrySetCFProperty(svc, "ReportInterval" as CFString, cfInterval!)
            IOObjectRelease(svc)
        }
        print("🛌 [MotionManager] Sensori Apple SPU messi a nanna (1Hz/Off)")
    }
}