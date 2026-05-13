import UIKit
import os

fileprivate enum Setting: Int, CaseIterable {
    case pairDevice = 0
    case clearDevices = 1
}

class SettingsViewGarminSettingsViewModel: NSObject {
    private var uIViewController: UIViewController?
    private var log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryTraceSettingsViewModel)
    private var messageHandler: ((String, String) -> Void)?
    private var rowReloadClosure: ((Int) -> Void)?
    
    override init() {
        super.init()
        GarminManager.shared.onStatusChange = { [weak self] in
            DispatchQueue.main.async {
                if let tableView = self?.uIViewController?.view.subviews.first(where: { $0 is UITableView }) as? UITableView {
                    tableView.reloadData()
                }
            }
        }
    }
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
        return "xDrip pushes data to your Garmin Glux Data Field. Multiple devices can receive data simultaneously if their data fields are active."
    }
    
    func settingsRowText(index: Int) -> String {
        let devices = GarminManager.shared.connectedDevices
        let actionCount = Setting.allCases.count
        
        if index < actionCount {
            guard let setting = Setting(rawValue: index) else { return "" }
            switch setting {
            case .pairDevice: return "Pair Garmin Device"
            case .clearDevices: return "Clear All Paired Devices"
            }
        } else {
            let deviceIndex = index - actionCount
            if deviceIndex < devices.count {
                return devices[deviceIndex].friendlyName ?? "Garmin Device"
            }
        }
        return ""
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        return (index == 0) ? .disclosureIndicator : .none
    }
    
    func detailedText(index: Int) -> String? {
        let actionCount = Setting.allCases.count
        if index == 0 {
            return "Launch Garmin Connect to add a device."
        } else if index == 1 {
            return "Remove all watches and bike computers from xDrip."
        } else {
            let devices = GarminManager.shared.connectedDevices
            let deviceIndex = index - actionCount
            if deviceIndex < devices.count {
                return GarminManager.shared.deviceStatusString(for: devices[deviceIndex])
            }
        }
        return nil
    }
    
    func uiView(index: Int) -> UIView? {
        return nil
    }
    
    func numberOfRows() -> Int {
        return Setting.allCases.count + GarminManager.shared.connectedDevices.count
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        let actionCount = Setting.allCases.count
        
        if index < actionCount {
            guard let setting = Setting(rawValue: index) else { return .nothing }
            switch setting {
            case .pairDevice:
                GarminManager.shared.showDeviceSelection()
            case .clearDevices:
                let alert = UIAlertController(title: "Clear All Devices?", message: "This will remove all paired Garmin devices from xDrip.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Clear", style: .destructive, handler: { _ in
                    GarminManager.shared.clearAllDevices()
                }))
                uIViewController?.present(alert, animated: true)
            }
        } else {
            let devices = GarminManager.shared.connectedDevices
            let deviceIndex = index - actionCount
            if deviceIndex < devices.count {
                let device = devices[deviceIndex]
                GarminManager.shared.pingDevice(device)
                
                // Show a brief feedback alert
                let alert = UIAlertController(title: "Pinging...", message: "Sending ping to \(device.friendlyName ?? "Garmin")...", preferredStyle: .alert)
                uIViewController?.present(alert, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    alert.dismiss(animated: true)
                }
            }
        }
        return .nothing
    }
    
    func isEnabled(index: Int) -> Bool {
        return true
    }
    
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool {
        return false
    }
}
