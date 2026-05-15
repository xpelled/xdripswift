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
    private var isSyncingDevices: Set<String> = []
    
    // Tracks which AppID a specific device is currently using
    private var deviceActiveAppId: [String: UUID] = [:]
    private let syncQueue = DispatchQueue(label: "com.xdrip.garmin.sync")
    
    // To prevent "Sync Storms" on frequent handshakes
    private var lastSentMessages: [String: [AnyHashable: Any]] = [:]
    private var debounceTimers: [String: Timer] = [:]
    
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
        if let ciq = ConnectIQ.sharedInstance() {
            for device in getSavedGarminDevices() {
                ciq.unregister(forDeviceEvents: device, delegate: self)
            }
        }
        #endif
        UserDefaults.standard.removeObject(forKey: "GarminManager_SavedDevices")
        UserDefaults.standard.removeObject(forKey: "GarminManager_Handshakes")
        UserDefaults.standard.removeObject(forKey: "GarminManager_DeviceSettings")
        UserDefaults.standard.removeObject(forKey: "GarminManager_PendingSettings")
        
        syncQueue.async {
            self.deviceHandshakes.removeAll()
            self.deviceActiveAppId.removeAll()
            self.deviceSettings.removeAll()
            self.pendingSettings.removeAll()
            self.isSyncingDevices.removeAll()
        }
        
        log("Cleared all Garmin devices and settings.")
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
        #else
        return false
        #endif
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
    
    public enum PriorityMode: Int {
        case none = 0
        case bg = 1
        case bgTime = 2
        case bgDelta = 3
        
        var description: String {
            switch self {
            case .none: return "Equal (Off)"
            case .bg: return "BG"
            case .bgTime: return "BG + Time"
            case .bgDelta: return "BG + Delta"
            }
        }
    }

    public enum TimerMode: Int {
        case off = 0
        case elapsed = 1
        case remaining = 2
        
        var description: String {
            switch self {
            case .off: return "Off"
            case .elapsed: return "Elapsed Time"
            case .remaining: return "Time Remaining"
            }
        }
    }
    
    // Settings for the Data Field (Per Device)
    private var deviceSettings: [String: [String: Any]] = [:]
    private var pendingSettings: [String: [String: Any]] = [:]
    
    public func getShowArrow(for deviceId: String) -> Bool {
        return deviceSettings[deviceId]?["showArrow"] as? Bool ?? true
    }
    
    public func setShowArrow(_ value: Bool, for deviceId: String) {
        updateSetting("showArrow", value: value, for: deviceId)
    }
    
    public func getRecordToFit(for deviceId: String) -> Bool {
        return deviceSettings[deviceId]?["recordToFit"] as? Bool ?? true
    }
    
    public func setRecordToFit(_ value: Bool, for deviceId: String) {
        updateSetting("recordToFit", value: value, for: deviceId)
    }
    
    public func getTimerMode(for deviceId: String) -> TimerMode {
        let val = deviceSettings[deviceId]?["timerMode"] as? Int ?? TimerMode.elapsed.rawValue
        return TimerMode(rawValue: val) ?? .elapsed
    }
    
    public func setTimerMode(_ mode: TimerMode, for deviceId: String) {
        updateSetting("timerMode", value: mode.rawValue, for: deviceId)
    }
    
    public func getShowDelta(for deviceId: String) -> Bool {
        return deviceSettings[deviceId]?["showDelta"] as? Bool ?? true
    }
    
    public func setShowDelta(_ value: Bool, for deviceId: String) {
        updateSetting("showDelta", value: value, for: deviceId)
    }
    
    public func getPriorityMode(for deviceId: String) -> PriorityMode {
        let val = deviceSettings[deviceId]?["priorityMode"] as? Int ?? 0
        return PriorityMode(rawValue: val) ?? .none
    }
    
    public func setPriorityMode(_ value: PriorityMode, for deviceId: String) {
        updateSetting("priorityMode", value: value.rawValue, for: deviceId)
    }
    
    private func updateSetting(_ key: String, value: Any, for deviceId: String) {
        let oldSettings = deviceSettings[deviceId] ?? [:]
        let oldValue = oldSettings[key]
        
        // Optimistic update
        var settings = oldSettings
        settings[key] = value
        deviceSettings[deviceId] = settings
        
        // Track as pending
        var pending = pendingSettings[deviceId] ?? [:]
        pending[key] = value
        pendingSettings[deviceId] = pending
        
        saveSettings()
        
        let rollback: [String: Any]? = oldValue != nil ? [key: oldValue!] : nil
        pushCurrentData(for: deviceId, rollbackValue: rollback)
    }
    
    private func pushCurrentData(for deviceId: String, rollbackValue: [String: Any]? = nil, retryCount: Int = 3) {
        #if canImport(ConnectIQ)
        // Debounce: wait 2 seconds before actual push to coalesce rapid handshakes/changes
        DispatchQueue.main.async { [weak self] in
            self?.debounceTimers[deviceId]?.invalidate()
            self?.debounceTimers[deviceId] = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.executePush(for: deviceId, rollbackValue: rollbackValue, retryCount: retryCount)
            }
        }
        #endif
    }
    
    private func executePush(for deviceId: String, rollbackValue: [String: Any]? = nil, retryCount: Int = 3) {
        #if canImport(ConnectIQ)
        guard let device = getSavedGarminDevices().first(where: { $0.uuid.uuidString == deviceId }) else { return }
        
        var data: (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?
        if Thread.isMainThread {
            data = garminDataProvider?()
        } else {
            DispatchQueue.main.sync {
                data = self.garminDataProvider?()
            }
        }
        
        guard let data = data else { return }
        
        let message: [AnyHashable: Any] = [
            "bgStr": data.bgStr,
            "trend": data.trendStr,
            "delta": data.deltaStr,
            "ts": data.timestamp,
            "bg": data.bgValue,
            "showArrow": self.getShowArrow(for: deviceId),
            "recordToFit": self.getRecordToFit(for: deviceId),
            "timerMode": self.getTimerMode(for: deviceId).rawValue,
            "showDelta": self.getShowDelta(for: deviceId),
            "priorityMode": self.getPriorityMode(for: deviceId).rawValue
        ]
        
        // Skip if identical to last message sent to this device
        if let last = lastSentMessages[deviceId], NSDictionary(dictionary: last).isEqual(to: message) {
            // log("Sync skip: Data identical for \(device.friendlyName ?? "Garmin")")
            return
        }
        
        pushViaConnectIQ(device: device, message: message, rollbackValue: rollbackValue, retryCount: retryCount)
        #endif
    }
    
    public func pushToGarmin(bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        guard Date().timeIntervalSince(lastPushTime) > 5.0 || lastPushTime == .distantPast else { return }
        
        #if canImport(ConnectIQ)
        let devices = getSavedGarminDevices()
        var pushed = false
        for device in devices {
            if isDataFieldActive(for: device) {
                // Use pushCurrentData to get benefit of debouncing/diffing
                pushCurrentData(for: device.uuid.uuidString)
                pushed = true
            }
        }
        if pushed { lastPushTime = Date() }
        #endif
    }

    private func pushViaConnectIQ(device: IQDevice, message: [AnyHashable: Any], rollbackValue: [String: Any]? = nil, retryCount: Int = 3) {
        #if canImport(ConnectIQ)
        let deviceId = device.uuid.uuidString
        
        var shouldSkip = false
        syncQueue.sync {
            if isSyncingDevices.contains(deviceId) {
                shouldSkip = true
            } else {
                isSyncingDevices.insert(deviceId)
            }
        }
        
        if shouldSkip {
            log("Sync skip: \(device.friendlyName ?? "Garmin") already in progress")
            // Schedule a deferred retry to ensure pending settings aren't lost
            DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.pushCurrentData(for: deviceId)
            }
            return
        }
        
        // Safety timeout to prevent permanent lock - increased to 25s for BLE congestion
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) { [weak self] in
            self?.syncQueue.async {
                if self?.isSyncingDevices.contains(deviceId) == true {
                    self?.log("Sync timeout: unlocking \(deviceId)")
                    self?.isSyncingDevices.remove(deviceId)
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let appId = self.deviceActiveAppId[deviceId] ?? self.devAppId!
            let app = IQApp(uuid: appId, store: nil, device: device)
            
            self.log("Pushing to \(device.friendlyName ?? "Garmin") [\(appId.uuidString.prefix(4))]")
            
            ConnectIQ.sharedInstance()?.sendMessage(message, to: app, progress: nil, completion: { [weak self] (result) in
                guard let self = self else { return }
                self.syncQueue.async { self.isSyncingDevices.remove(deviceId) }
                
                if result == .success {
                    self.log("Sync OK: \(device.friendlyName ?? "Garmin")")
                    self.lastSentMessages[deviceId] = message
                    self.pendingSettings[deviceId] = nil // Clear pending on success
                    self.saveSettings()
                    NotificationCenter.default.post(name: GarminManager.GarminSettingsSyncResult, object: nil, userInfo: ["success": true, "deviceId": deviceId])
                } else {
                    self.log("Sync Error [\(result.rawValue)]: \(device.friendlyName ?? "Garmin")")
                    
                    if result.rawValue == 4 {
                        self.log("Sync Aborted: App not running on \(device.friendlyName ?? "Garmin")")
                        return // Do not retry if app is not running
                    }
                    
                    let currentStatus = ConnectIQ.sharedInstance()?.getDeviceStatus(device) ?? .notConnected
                    if currentStatus != .connected {
                        self.log("Sync Parked (Disconnected): \(device.friendlyName ?? "Garmin")")
                    } else if retryCount > 0 {
                        self.log("Retrying \(device.friendlyName ?? "Garmin") (\(retryCount) left)...")
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
        if let saved = UserDefaults.standard.dictionary(forKey: "GarminManager_DeviceSettings") as? [String: [String: Any]] {
            self.deviceSettings = saved
        }
        if let pending = UserDefaults.standard.dictionary(forKey: "GarminManager_PendingSettings") as? [String: [String: Any]] {
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
            if let tMode = dict["timerMode"] as? Int { settings["timerMode"] = tMode }
            if let sDelta = dict["showDelta"] as? Bool { settings["showDelta"] = sDelta }
            if let pMode = dict["priorityMode"] as? Int { settings["priorityMode"] = pMode }
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
            
            if let _ = data {
                pushCurrentData(for: deviceId)
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
