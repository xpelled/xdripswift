import Foundation
import CoreData
#if canImport(ConnectIQ)
import ConnectIQ
#endif

public class GarminManager: NSObject {
    public static let shared = GarminManager()
    
    public static let GarminHandshakeReceived = Notification.Name("GarminHandshakeReceived")
    
    // Support for both Dev and Beta versions
    private let devAppId = UUID(uuidString: "A3421FEE-D289-106A-538C-B9547AB3F101")
    private let betaAppId = UUID(uuidString: "B37A01FE-ED28-9106-A538-CB9547AB3F01")
    
    private var validAppIds: [UUID] {
        return [devAppId, betaAppId].compactMap { $0 }
    }
    
    public var garminDataProvider: (() -> (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?)?
    public var onStatusChange: (() -> Void)?
    
    private var lastPushTime: Date = .distantPast
    private var deviceHandshakes: [String: Date] = [:]
    
    // Tracks which AppID a specific device is currently using
    private var deviceActiveAppId: [String: UUID] = [:]
    
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
        deviceActiveAppId.removeAll()
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
        // Ping all possible AppIDs since we don't know which one is installed
        for appId in validAppIds {
            let app = IQApp(uuid: appId, store: nil, device: device)
            ConnectIQ.sharedInstance()?.sendMessage(["cmd": "ping"], to: app, progress: nil, completion: { [weak self] (result) in
                if result == .success {
                    self?.log("Ping sent to \(device.friendlyName ?? "Garmin") (\(appId.uuidString.prefix(4))...)")
                }
            })
        }
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
    
    // Settings for the Data Field
    public var showArrow: Bool {
        get { UserDefaults.standard.bool(forKey: "GarminManager_ShowArrow") == false ? true : UserDefaults.standard.bool(forKey: "GarminManager_ShowArrow") } // Default true
        set { 
            UserDefaults.standard.set(newValue, forKey: "GarminManager_ShowArrow")
            pushCurrentData() 
        }
    }
    
    public var recordToFit: Bool {
        get { UserDefaults.standard.object(forKey: "GarminManager_RecordToFit") as? Bool ?? true } // Default true
        set { 
            UserDefaults.standard.set(newValue, forKey: "GarminManager_RecordToFit")
            pushCurrentData()
        }
    }
    
    private func pushCurrentData() {
        if let provider = garminDataProvider, let data = provider() {
            pushToGarmin(bgStr: data.bgStr, trendStr: data.trendStr, deltaStr: data.deltaStr, timestamp: data.timestamp, bgValue: data.bgValue)
        }
    }
    
    public func pushToGarmin(bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        guard Date().timeIntervalSince(lastPushTime) > 5.0 || lastPushTime == .distantPast else { return }
        
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
        // Use the specifically identified active AppID for this device, or fallback to Dev
        let appId = deviceActiveAppId[device.uuid.uuidString] ?? devAppId!
        let app = IQApp(uuid: appId, store: nil, device: device)
        
        let message: [AnyHashable: Any] = [
            "bgStr": bgStr,
            "trend": trendStr,
            "delta": deltaStr,
            "ts": timestamp,
            "bg": bgValue,
            "showArrow": showArrow,
            "recordToFit": recordToFit
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
        
        // Remember which version of the app is actually talking to us
        self.deviceActiveAppId[deviceId] = app.uuid
        
        if cmd == "ready" {
            log("Handshake from \(app.device.friendlyName ?? "device") [\(app.uuid.uuidString.prefix(4))]")
            self.deviceHandshakes[deviceId] = Date()
            saveHandshakes()
            
            if let provider = garminDataProvider, let data = provider() {
                pushViaConnectIQ(device: app.device, bgStr: data.bgStr, trendStr: data.trendStr, deltaStr: data.deltaStr, timestamp: data.timestamp, bgValue: data.bgValue)
            }
            
            NotificationCenter.default.post(name: GarminManager.GarminHandshakeReceived, object: nil, userInfo: ["deviceName": app.device.friendlyName ?? "Garmin"])
        } else if cmd == "stop" {
            log("Stop signal from \(app.device.friendlyName ?? "device")")
            self.deviceHandshakes.removeValue(forKey: deviceId)
            self.deviceActiveAppId.removeValue(forKey: deviceId)
            saveHandshakes()
        }
        
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?() }
    }
}

extension GarminManager {
    func registerForAppMessages(device: IQDevice) {
        for appId in validAppIds {
            let app = IQApp(uuid: appId, store: nil, device: device)
            ConnectIQ.sharedInstance()?.register(forAppMessages: app, delegate: self)
        }
    }
}
#endif
