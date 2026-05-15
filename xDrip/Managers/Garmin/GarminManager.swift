import Foundation
import CoreData
#if canImport(ConnectIQ)
import ConnectIQ
#endif

public class GarminManager: NSObject {
    public static let shared = GarminManager()
    
    public static let GarminHandshakeReceived = Notification.Name("GarminHandshakeReceived")
    public static let GarminSettingsSyncResult = Notification.Name("GarminManager_SettingsSyncResult")
    
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
        loadSettings()
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
        UserDefaults.standard.removeObject(forKey: "GarminManager_DeviceSettings")
        deviceHandshakes.removeAll()
        deviceActiveAppId.removeAll()
        deviceSettings.removeAll()
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
    
    // Settings for the Data Field (Per Device)
    private var deviceSettings: [String: [String: Bool]] = [:]
    private var pendingSettings: [String: [String: Bool]] = [:]
    
    public func getShowArrow(for deviceId: String) -> Bool {
        return deviceSettings[deviceId]?["showArrow"] ?? true
    }
    
    public func setShowArrow(_ value: Bool, for deviceId: String) {
        let oldValue = getShowArrow(for: deviceId)
        
        // Optimistic update
        var settings = deviceSettings[deviceId] ?? [:]
        settings["showArrow"] = value
        deviceSettings[deviceId] = settings
        
        // Track as pending
        var pending = pendingSettings[deviceId] ?? [:]
        pending["showArrow"] = value
        pendingSettings[deviceId] = pending
        
        saveSettings()
        pushCurrentData(for: deviceId, rollbackValue: ["showArrow": oldValue])
    }
    
    public func getRecordToFit(for deviceId: String) -> Bool {
        return deviceSettings[deviceId]?["recordToFit"] ?? true
    }
    
    public func setRecordToFit(_ value: Bool, for deviceId: String) {
        let oldValue = getRecordToFit(for: deviceId)
        
        // Optimistic update
        var settings = deviceSettings[deviceId] ?? [:]
        settings["recordToFit"] = value
        deviceSettings[deviceId] = settings
        
        // Track as pending
        var pending = pendingSettings[deviceId] ?? [:]
        pending["recordToFit"] = value
        pendingSettings[deviceId] = pending
        
        saveSettings()
        pushCurrentData(for: deviceId, rollbackValue: ["recordToFit": oldValue])
    }
    
    private func pushCurrentData(for deviceId: String, rollbackValue: [String: Bool]? = nil, retryCount: Int = 3) {
        #if canImport(ConnectIQ)
        guard let device = getSavedGarminDevices().first(where: { $0.uuid.uuidString == deviceId }) else { return }
        
        // Check if device is even reachable before trying
        let status = ConnectIQ.sharedInstance()?.getDeviceStatus(device) ?? .notConnected
        if status != .connected {
            log("Device \(device.friendlyName ?? "") disconnected. Settings 'parked' for later.")
            return // Keep in pendingSettings, will retry on reconnect
        }
        
        var data: (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?
        if Thread.isMainThread {
            data = garminDataProvider?()
        } else {
            DispatchQueue.main.sync {
                data = self.garminDataProvider?()
            }
        }
        
        if let data = data {
            pushViaConnectIQ(device: device, bgStr: data.bgStr, trendStr: data.trendStr, deltaStr: data.deltaStr, timestamp: data.timestamp, bgValue: data.bgValue, rollbackValue: rollbackValue, retryCount: retryCount)
        }
        #endif
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

    private func pushViaConnectIQ(device: IQDevice, bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float, rollbackValue: [String: Bool]? = nil, retryCount: Int = 3) {
        #if canImport(ConnectIQ)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let deviceId = device.uuid.uuidString
            let appId = self.deviceActiveAppId[deviceId] ?? self.devAppId!
            let app = IQApp(uuid: appId, store: nil, device: device)
            
            let message: [AnyHashable: Any] = [
                "bgStr": bgStr,
                "trend": trendStr,
                "delta": deltaStr,
                "ts": timestamp,
                "bg": bgValue,
                "showArrow": self.getShowArrow(for: deviceId),
                "recordToFit": self.getRecordToFit(for: deviceId)
            ]
            
            ConnectIQ.sharedInstance()?.sendMessage(message, to: app, progress: nil, completion: { [weak self] (result) in
                guard let self = self else { return }
                
                if result == .success {
                    self.log("Sync OK: \(device.friendlyName ?? "Garmin")")
                    self.pendingSettings[deviceId] = nil // Clear pending on success
                    self.saveSettings()
                    NotificationCenter.default.post(name: GarminManager.GarminSettingsSyncResult, object: nil, userInfo: ["success": true, "deviceId": deviceId])
                } else {
                    let currentStatus = ConnectIQ.sharedInstance()?.getDeviceStatus(device) ?? .notConnected
                    if currentStatus != .connected {
                        self.log("Sync Parked (Disconnected): \(device.friendlyName ?? "Garmin")")
                        self.saveSettings() // Persist parked state
                        // Do not post failure, just keep in pending
                    } else if retryCount > 0 {
                        self.log("Sync Retrying (\(retryCount) left): \(device.friendlyName ?? "Garmin") error: \(result.rawValue)")
                        // Retry after 2 seconds
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                            self.pushCurrentData(for: deviceId, rollbackValue: rollbackValue, retryCount: retryCount - 1)
                        }
                    } else {
                        // PERMANENT FAILURE - ROLLBACK
                        self.log("Sync FATAL: \(device.friendlyName ?? "Garmin"). Rolling back.")
                        if let rollback = rollbackValue {
                            var settings = self.deviceSettings[deviceId] ?? [:]
                            for (key, val) in rollback {
                                settings[key] = val
                            }
                            self.deviceSettings[deviceId] = settings
                            self.saveSettings()
                            DispatchQueue.main.async { self.onStatusChange?() }
                        }
                        self.pendingSettings[deviceId] = nil
                        self.saveSettings()
                        DispatchQueue.main.async { self.onStatusChange?() }
                        NotificationCenter.default.post(name: GarminManager.GarminSettingsSyncResult, object: nil, userInfo: ["success": false, "deviceId": deviceId, "error": "\(result.rawValue)"])
                    }
                }
            })
        }
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
    
    private func saveSettings() {
        UserDefaults.standard.set(deviceSettings, forKey: "GarminManager_DeviceSettings")
        UserDefaults.standard.set(pendingSettings, forKey: "GarminManager_PendingSettings")
    }
    
    private func loadSettings() {
        if let saved = UserDefaults.standard.dictionary(forKey: "GarminManager_DeviceSettings") as? [String: [String: Bool]] {
            self.deviceSettings = saved
        }
        if let pending = UserDefaults.standard.dictionary(forKey: "GarminManager_PendingSettings") as? [String: [String: Bool]] {
            self.pendingSettings = pending
        }
    }
}

#if canImport(ConnectIQ)
extension GarminManager: IQDeviceEventDelegate {
    public func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        log("Device \(device.friendlyName ?? "") status: \(status.rawValue)")
        
        // If device reconnected, push any pending settings
        if status == .connected && pendingSettings[device.uuid.uuidString] != nil {
            log("Device \(device.friendlyName ?? "") reconnected. Pushing pending settings...")
            pushCurrentData(for: device.uuid.uuidString)
        }
        
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
            
            // SYNC SETTINGS FROM WATCH
            var settings = deviceSettings[deviceId] ?? [:]
            if let sArrow = dict["showArrow"] as? Bool { settings["showArrow"] = sArrow }
            if let rFit = dict["recordToFit"] as? Bool { settings["recordToFit"] = rFit }
            deviceSettings[deviceId] = settings
            saveSettings()
            
            self.deviceHandshakes[deviceId] = Date()
            saveHandshakes()
            
            var data: (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?
            if Thread.isMainThread {
                data = garminDataProvider?()
            } else {
                DispatchQueue.main.sync {
                    data = self.garminDataProvider?()
                }
            }
            
            if let data = data {
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
