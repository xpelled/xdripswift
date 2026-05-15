import UIKit

class SettingsViewGluxDevicesViewModel: NSObject, SettingsViewModelProtocol {
    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {}
    func storeUIViewController(uIViewController: UIViewController) {}
    func storeMessageHandler(messageHandler: @escaping ((String, String) -> Void)) {}
    
    func sectionTitle() -> String? {
        return "Paired Devices"
    }
    
    func sectionFooter() -> String? {
        return "Tap a device to send a test ping. Active devices will show as 'Active'."
    }
    
    func settingsRowText(index: Int) -> String {
        let devices = GarminManager.shared.connectedDevices
        if index < devices.count {
            return devices[index].friendlyName ?? "Garmin Device"
        }
        return ""
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        return .none
    }
    
    func detailedText(index: Int) -> String? {
        let devices = GarminManager.shared.connectedDevices
        if index < devices.count {
            return GarminManager.shared.deviceStatusString(for: devices[index])
        }
        return nil
    }
    
    func uiView(index: Int) -> UIView? { return nil }
    
    func numberOfRows() -> Int {
        return GarminManager.shared.connectedDevices.count
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        let devices = GarminManager.shared.connectedDevices
        if index < devices.count {
            let device = devices[index]
            GarminManager.shared.pingDevice(device)
            return .nothing
        }
        return .nothing
    }
    
    func isEnabled(index: Int) -> Bool { return true }
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool { return false }
}
