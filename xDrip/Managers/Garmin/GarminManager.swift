import Foundation
import CoreData
#if canImport(ConnectIQ)
import ConnectIQ
#endif

public enum GarminConnectionType: Int {
    case connectIQ = 0
    case ble = 1
}

public class GarminManager: NSObject {
    public static let shared = GarminManager()
    
    /// The unique UUID of your Garmin Data Field (from manifest.xml)
    private let garminAppId = UUID(uuidString: "A3421FEE-D289-106A-538C-B9547AB3F101")
    
    /// Closure that provides Garmin data components on demand (injected by RootViewController)
    public var garminDataProvider: (() -> (bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float)?)?
    
    private override init() {
        super.init()
        #if canImport(ConnectIQ)
        if let device = getSavedGarminDevice() as? IQDevice {
            ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)
            registerForAppMessages(device: device)
            print("GarminManager initialized: Registered saved device \(device.friendlyName ?? "")")
        }
        #endif
    }
    
    public func showDeviceSelection() {
        #if canImport(ConnectIQ)
        ConnectIQ.sharedInstance()?.showDeviceSelection()
        #else
        print("ConnectIQ framework not imported.")
        #endif
    }
    
    public func handleOpenURL(_ url: URL) -> Bool {
        #if canImport(ConnectIQ)
        if url.scheme == "xdrip-garmin" {
            if let devices = ConnectIQ.sharedInstance()?.parseDeviceSelectionResponse(from: url) as? [IQDevice], let firstDevice = devices.first {
                saveGarminDevice(firstDevice)
                ConnectIQ.sharedInstance()?.register(forDeviceEvents: firstDevice, delegate: self)
                registerForAppMessages(device: firstDevice)
                print("Garmin device paired successfully!")
                return true
            }
        }
        #endif
        return false
    }
    
    /// Push BG data components to the Garmin data field
    public func pushToGarmin(bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        let connectionType = GarminConnectionType(rawValue: UserDefaults.standard.garminConnectionType) ?? .connectIQ
        
        switch connectionType {
        case .connectIQ:
            pushViaConnectIQ(bgStr: bgStr, trendStr: trendStr, deltaStr: deltaStr, timestamp: timestamp, bgValue: bgValue)
        case .ble:
            print("BLE push not implemented yet.")
        }
    }
    
    public func saveGarminDevice(_ device: IQDevice) {
        #if canImport(ConnectIQ)
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: device, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "GarminManager_SavedDevice")
        } catch {
            print("Failed to save Garmin device: \(error)")
        }
        #endif
    }
    
    public func getSavedGarminDevice() -> Any? {
        #if canImport(ConnectIQ)
        guard let data = UserDefaults.standard.data(forKey: "GarminManager_SavedDevice") else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: IQDevice.self, from: data)
        } catch {
            print("Failed to load Garmin device: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private func pushViaConnectIQ(bgStr: String, trendStr: String, deltaStr: String, timestamp: Int, bgValue: Float) {
        #if canImport(ConnectIQ)
        guard let appId = garminAppId else { return }
        
        guard let device = getSavedGarminDevice() as? IQDevice else {
            print("No Garmin device saved. Please pair using ConnectIQ.sharedInstance()?.showDeviceSelection()")
            return
        }
        
        let app = IQApp(uuid: appId, store: nil, device: device)
        
        let message: [AnyHashable: Any] = [
            "bgStr": bgStr,
            "trend": trendStr,
            "delta": deltaStr,
            "ts": timestamp,
            "bg": bgValue
        ]
        
        // Register for events to ensure the SDK tries to connect
        ConnectIQ.sharedInstance()?.register(forDeviceEvents: device, delegate: self)
        
        if let status = ConnectIQ.sharedInstance()?.getDeviceStatus(device) {
            print("Garmin device status before send: \(status.rawValue)")
        }
        
        ConnectIQ.sharedInstance()?.sendMessage(message, to: app, progress: { (sent, total) in
            // Handle progress
        }, completion: { (result) in
            if result == .success {
                print("Successfully sent to Garmin: \(bgStr) \(trendStr) \(deltaStr)")
            } else {
                print("Failed to send BG to Garmin. Result code: \(result.rawValue)")
            }
        })
        #else
        print("ConnectIQ framework not imported. Cannot push via Connect IQ.")
        #endif
    }
}

#if canImport(ConnectIQ)
extension GarminManager: IQDeviceEventDelegate {
    public func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        print("Garmin device status changed: \(status.rawValue)")
    }
    
    public func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        print("Garmin device characteristics discovered, ready to communicate!")
    }
}

extension GarminManager: IQAppMessageDelegate {
    public func receivedMessage(_ message: Any!, from app: IQApp!) {
        print("Received message from Garmin data field: \(String(describing: message))")
        
        // The data field sent a 'ready' message — push the latest BG immediately
        if let provider = garminDataProvider, let data = provider() {
            pushToGarmin(bgStr: data.bgStr, trendStr: data.trendStr, deltaStr: data.deltaStr, timestamp: data.timestamp, bgValue: data.bgValue)
            print("Pushed latest BG to Garmin on data field request")
        } else {
            print("No BG data available to push to Garmin on request")
        }
    }
}

extension GarminManager {
    /// Register to receive messages from the Glux data field app on the given device
    func registerForAppMessages(device: IQDevice) {
        guard let appId = garminAppId else { return }
        let app = IQApp(uuid: appId, store: nil, device: device)
        ConnectIQ.sharedInstance()?.register(forAppMessages: app, delegate: self)
        print("Registered for app messages from Garmin data field")
    }
}
#endif
