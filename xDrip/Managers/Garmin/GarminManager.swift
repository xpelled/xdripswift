import Foundation
import CoreData
#if canImport(ConnectIQ)
import ConnectIQ
#endif

public class GarminManager: NSObject {
    public static let shared = GarminManager()
    
    private let garminAppId = UUID(uuidString: "A3421FEE-D289-106A-538C-B9547AB3F101")
    
    public var garminDataProvider: (() -> (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?)?
    public var onStatusChange: (() -> Void)?
    
    private var lastPushTime: Date = .distantPast
    private var deviceHandshakes: [String: Date] = [:]
    
    private override init() {
        super.init()
        loadHandshakes()
        #if canImport(ConnectIQ)
        let devices = getSavedGarminDevices()
        for device in devices {
            ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)
            registerForAppMessages(device: device)
        }
        #endif
    }
    
    private func log(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("\(formatter.string(from: Date())) [Garmin] \(msg)")
    }
    
    public func showDeviceSelection() {
        #if canImport(ConnectIQ)
        ConnectIQ.sharedInstance()?.showDeviceSelection()
        #endif
    }
    
    public func clearAllDevices() {
        #if canImport(ConnectIQ)
        for device in getSavedGarminDevices() {
            ConnectIQ.sharedInstance()?.unregister(forDeviceEvents: device, delegate: self)
        }
        #endif
        UserDefaults.standard.removeObject(forKey: "GarminManager_SavedDevices")
        UserDefaults.standard.removeObject(forKey: "GarminManager_Handshakes")
        deviceHandshakes.removeAll()
        log("Cleared all Garmin devices.")
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
    
    public func handleOpenURL(_ url: URL) -> Bool {
        #if canImport(ConnectIQ)
        guard let devices = ConnectIQ.sharedInstance()?.parseDeviceSelectionResponse(from: url) as? [IQDevice] else {
            return false
        }
        
        var savedDevices = getSavedGarminDevices()
        var newlyAdded = false
        
        for device in devices {
            if !savedDevices.contains(where: { $0.uuid.uuidString == device.uuid.uuidString }) {
                savedDevices.append(device)
                newlyAdded = true
                log("Added device: \(device.friendlyName ?? "Unknown")")
            }
            
            ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)
            registerForAppMessages(device: device)
            
            // Mark as active immediately on pairing
            self.deviceHandshakes[device.uuid.uuidString] = Date()
        }
        
        if newlyAdded {
            saveGarminDevices(savedDevices)
        }
        saveHandshakes()
        
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
        return true
        #endif
        return false
    }

    public func pingDevice(_ device: IQDevice) {
        #if canImport(ConnectIQ)
        let app = IQApp(uuid: garminAppId!, store: nil, device: device)
        log("Pinging \(device.friendlyName ?? "Garmin")...")
        ConnectIQ.sharedInstance()?.sendMessage(["cmd": "ping"], to: app, progress: nil, completion: { [weak self] (result) in
            if result != .success {
                self?.log("Ping failed: \(result.rawValue)")
            }
        })
        #endif
    }
    
    public func isDataFieldActive(for device: IQDevice) -> Bool {
        guard let lastHandshake = deviceHandshakes[device.uuid.uuidString] else { return false }
        // 5 minutes is enough since watch pings every 3 minutes
        return Date().timeIntervalSince(lastHandshake) < 300.0
    }

    public var connectedDevices: [IQDevice] {
        return getSavedGarminDevices()
    }
    
    public func deviceStatusString(for device: IQDevice) -> String {
        #if canImport(ConnectIQ)
        let status = ConnectIQ.sharedInstance()?.getDeviceStatus(device) ?? .notConnected
        var statusStr = (status == .connected) ? "Connected" : "Disconnected"
        if status == .connected {
            statusStr += isDataFieldActive(for: device) ? " (Active)" : " (Standby)"
        }
        return statusStr
        #else
        return "N/A"
        #endif
    }
    
    public func pushToGarmin(bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        guard Date().timeIntervalSince(lastPushTime) > 5.0 else { return }
        
        #if canImport(ConnectIQ)
        let devices = getSavedGarminDevices()
        var pushed = false
        for device in devices {
            if isDataFieldActive(for: device) {
                pushViaConnectIQ(device: device, bgStr: bgStr, trendStr: trendStr, deltaStr: deltaStr, timestamp: timestamp, bgValue: bgValue)
                pushed = true
            }
        }
        if pushed { lastPushTime = Date() }
        #endif
    }

    private func pushViaConnectIQ(device: IQDevice, bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        #if canImport(ConnectIQ)
        let app = IQApp(uuid: garminAppId!, store: nil, device: device)
        let message: [AnyHashable: Any] = [
            "bgStr": bgStr,
            "trend": trendStr,
            "delta": deltaStr,
            "ts": timestamp,
            "bg": bgValue
        ]
        
        ConnectIQ.sharedInstance()?.sendMessage(message, to: app, progress: nil, completion: { [weak self] (result) in
            if result == .success {
                self?.log("Pushed to \(device.friendlyName ?? "Garmin") (\(bgStr))")
            } else {
                self?.log("Failed push to \(device.friendlyName ?? "Garmin"): \(result.rawValue)")
            }
        })
        #endif
    }
    
    private func saveGarminDevices(_ devices: [IQDevice]) {
        #if canImport(ConnectIQ)
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "GarminManager_SavedDevices")
        } catch { log("Error saving devices: \(error)") }
        #endif
    }
    
    private func getSavedGarminDevices() -> [IQDevice] {
        #if canImport(ConnectIQ)
        guard let data = UserDefaults.standard.data(forKey: "GarminManager_SavedDevices") else { return [] }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, IQDevice.self], from: data) as? [IQDevice] ?? []
        } catch { return [] }
        #else
        return []
        #endif
    }
    
    private func saveHandshakes() {
        UserDefaults.standard.set(deviceHandshakes, forKey: "GarminManager_Handshakes")
    }
    
    private func loadHandshakes() {
        if let saved = UserDefaults.standard.dictionary(forKey: "GarminManager_Handshakes") as? [String: Date] {
            // Only load handshakes that are less than 5 minutes old
            self.deviceHandshakes = saved.filter { Date().timeIntervalSince($0.value) < 300.0 }
        }
    }
}

#if canImport(ConnectIQ)
extension GarminManager: IQDeviceEventDelegate {
    public func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        log("Device \(device.friendlyName ?? "") status: \(status.rawValue)")
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
}

extension GarminManager: IQAppMessageDelegate {
    public func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let dict = message as? [String: Any], let cmd = dict["cmd"] as? String else { return }
        let deviceId = app.device.uuid.uuidString
        
        if cmd == "ready" {
            log("Handshake from \(app.device.friendlyName ?? "device")")
            self.deviceHandshakes[deviceId] = Date()
            saveHandshakes()
            
            if let provider = garminDataProvider, let data = provider() {
                pushViaConnectIQ(device: app.device, bgStr: data.bgStr, trendStr: data.trendStr, deltaStr: data.deltaStr, timestamp: data.timestamp, bgValue: data.bgValue)
            }
        } else if cmd == "stop" {
            log("Stop signal from \(app.device.friendlyName ?? "device")")
            self.deviceHandshakes.removeValue(forKey: deviceId)
            saveHandshakes()
        }
        
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
}

extension GarminManager {
    func registerForAppMessages(device: IQDevice) {
        let app = IQApp(uuid: garminAppId!, store: nil, device: device)
        ConnectIQ.sharedInstance()?.register(forAppMessages: app, delegate: self)
    }
}
#endif
