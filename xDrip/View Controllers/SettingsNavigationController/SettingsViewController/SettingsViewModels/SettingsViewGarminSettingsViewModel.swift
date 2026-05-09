import UIKit
import os

fileprivate enum Setting: Int, CaseIterable {
    case pairDevice = 0
    case connectionType = 1
}

class SettingsViewGarminSettingsViewModel: NSObject {
    private var uIViewController: UIViewController?
    private var log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryTraceSettingsViewModel)
    private var messageHandler: ((String, String) -> Void)?
    private var rowReloadClosure: ((Int) -> Void)?
}

extension SettingsViewGarminSettingsViewModel: SettingsViewModelProtocol {
    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {
        self.rowReloadClosure = rowReloadClosure
    }
    
    func storeUIViewController(uIViewController: UIViewController) {
        self.uIViewController = uIViewController
    }

    func storeMessageHandler(messageHandler: @escaping ((String, String) -> Void)) {
        self.messageHandler = messageHandler
    }
    
    func sectionTitle() -> String? {
        return "⌚️ Garmin Integration"
    }
    
    func sectionFooter() -> String? {
        return "Select how xDrip communicates with your Garmin Glux Data Field. By default, data is pushed via the Garmin Connect app. You must pair a device before data can be sent."
    }
    
    func settingsRowText(index: Int) -> String {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        switch setting {
        case .pairDevice:
            return "Pair Garmin Device"
        case .connectionType:
            return "Use BLE Peripheral"
        }
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        switch setting {
        case .pairDevice:
            return .disclosureIndicator
        case .connectionType:
            return .none
        }
    }
    
    func detailedText(index: Int) -> String? {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        switch setting {
        case .pairDevice:
            return "Launch Garmin Connect to select your watch."
        case .connectionType:
            return "Enable to broadcast directly via BLE instead of using the Garmin Connect app."
        }
    }
    
    func uiView(index: Int) -> UIView? {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        switch setting {
        case .pairDevice:
            return nil
        case .connectionType:
            let type = GarminConnectionType(rawValue: UserDefaults.standard.garminConnectionType) ?? .connectIQ
            let switchView = UISwitch(isOn: type == .ble) { [weak self] isOn in
                if isOn {
                    self?.messageHandler?("BLE Peripheral", "Direct BLE broadcasting to Garmin is not available at the moment. Falling back to Garmin Connect app.")
                    UserDefaults.standard.garminConnectionType = GarminConnectionType.connectIQ.rawValue
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.rowReloadClosure?(index)
                    }
                } else {
                    UserDefaults.standard.garminConnectionType = GarminConnectionType.connectIQ.rawValue
                }
            }
            return switchView
        }
    }
    
    func numberOfRows() -> Int {
        return Setting.allCases.count
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        switch setting {
        case .pairDevice:
            GarminManager.shared.showDeviceSelection()
            return .nothing
        case .connectionType:
            return .nothing
        }
    }
    
    func isEnabled(index: Int) -> Bool {
        return true
    }
    
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool {
        return false
    }
}
