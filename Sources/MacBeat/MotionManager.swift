import Foundation
import IOKit.hid

final class MotionManager: ObservableObject {
    @Published var isMonitoring: Bool = false
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
    
    // Cambiato: ora passa (LatoLogico, TipoFisico)
    var onTapDetected: ((String, String) -> Void)?

    private var hidManager: IOHIDManager?
    fileprivate var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var gravityX: Double = 0
    private var gravityZ: Double = 0
    private var prevLinearX: Double = 0
    private var prevLinearZ: Double = 0
    private let lockoutDuration: TimeInterval = 0.11
    private var lastTap: TimeInterval = 0
    private var isCollecting: Bool = false
    private var collectionStartTime: TimeInterval = 0
    private let collectionWindowDuration: TimeInterval = 0.015
    private var peakJerkX: Double = 0
    private var peakJerkZ: Double = 0
    
    /// Numero di report da saltare all'avvio per stabilizzare i filtri
    private var isFirstReport: Bool = true

    static let shared = MotionManager()

    private init() {
        wakeSPUDrivers()
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 22)
    }

    func startMonitoring() {
        guard let manager = hidManager else { return }
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 3] as CFDictionary)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let m = Unmanaged<MotionManager>.fromOpaque(context!).takeUnretainedValue()
            IOHIDDeviceRegisterInputReportCallback(device, m.reportBuffer!, 22, { context, _, _, _, _, report, _ in
                Unmanaged<MotionManager>.fromOpaque(context!).takeUnretainedValue().process(report)
            }, context)
        }, selfPtr)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func process(_ report: UnsafePointer<UInt8>) {
        guard isMonitoring else { return }
        let xRaw = Int32(bitPattern: (UInt32(report[9])  << 24) | (UInt32(report[8])  << 16) | (UInt32(report[7])  << 8) | UInt32(report[6]))
        let zRaw = Int32(bitPattern: (UInt32(report[17]) << 24) | (UInt32(report[16]) << 16) | (UInt32(report[15]) << 8) | UInt32(report[14]))
        let x = Double(xRaw) / 65536.0
        let z = Double(zRaw) / 65536.0

        if isFirstReport {
            gravityX = x
            gravityZ = z
            prevLinearX = 0
            prevLinearZ = 0
            isFirstReport = false
            return
        }

        gravityX = (x * 0.1) + (gravityX * 0.9)
        gravityZ = (z * 0.1) + (gravityZ * 0.9)
        let linearX = x - gravityX
        let linearZ = z - gravityZ
        let jerkX = linearX - prevLinearX
        let jerkZ = linearZ - prevLinearZ
        prevLinearX = linearX
        prevLinearZ = linearZ

        let threshold: Double
        switch sensitivityLevel {
        case 1: threshold = 0.010    // Low (Old 50)
        case 2: threshold = 0.008    // Med (Old 60)
        case 3: threshold = 0.006    // High (Old 70)
        case 4: threshold = 0.004    // Extra (Old 80)
        case 5: threshold = 0.0025   // Max (Old 90ish)
        default: threshold = 0.010
        }
        let now = ProcessInfo.processInfo.systemUptime

        if isCollecting {
            if abs(jerkX) > abs(peakJerkX) { peakJerkX = jerkX }
            if abs(jerkZ) > abs(peakJerkZ) { peakJerkZ = jerkZ }
            if (now - collectionStartTime) >= collectionWindowDuration { fireTap(at: now) }
            return
        }

        guard (now - lastTap) > lockoutDuration else { return }
        if max(abs(jerkX), abs(jerkZ)) > threshold {
            isCollecting = true
            collectionStartTime = now
            peakJerkX = jerkX
            peakJerkZ = jerkZ
        }
    }

    private func fireTap(at now: TimeInterval) {
        isCollecting = false
        lastTap = now
        let xMagnitude = abs(peakJerkX)
        let zMagnitude = abs(peakJerkZ)
        let isSideTap = xMagnitude > (zMagnitude * 0.35)
        
        let rawTapType = isSideTap ? "SIDE" : "TOP"
        let side = isSideTap ? "LEFT" : "RIGHT" // SIDE -> Left (Snare), TOP -> Right (Kick)

        DispatchQueue.main.async { self.onTapDetected?(side, rawTapType) }
    }

    private func wakeSPUDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        while true {
            let svc = IOIteratorNext(iterator)
            if svc == 0 { break }
            var n: Int32 = 1
            let cf = CFNumberCreate(nil, .sInt32Type, &n)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, cf!)
            IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState" as CFString, cf!)
            IOObjectRelease(svc)
        }
    }
}