import UIKit

fileprivate enum Setting: Int, CaseIterable {
    case pairDevice = 0
    case clearDevices = 1
}

class SettingsViewGluxManagementViewModel: NSObject, SettingsViewModelProtocol {
    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {}
    func storeUIViewController(uIViewController: UIViewController) {}
    func storeMessageHandler(messageHandler: @escaping ((String, String) -> Void)) {}
    
    func sectionTitle() -> String? {
        return "Management"
    }
    
    func sectionFooter() -> String? {
        return "Use 'Pair' to find new devices via Garmin Connect. 'Clear' will remove all watches from xDrip."
    }
    
    func settingsRowText(index: Int) -> String {
        guard let setting = Setting(rawValue: index) else { return "" }
        switch setting {
        case .pairDevice: return "Pair New Garmin Device"
        case .clearDevices: return "Clear All Paired Devices"
        }
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        return (index == 0) ? .disclosureIndicator : .none
    }
    
    func detailedText(index: Int) -> String? {
        return nil
    }
    
    func uiView(index: Int) -> UIView? { return nil }
    
    func numberOfRows() -> Int {
        return Setting.allCases.count
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        guard let setting = Setting(rawValue: index) else { return .nothing }
        switch setting {
        case .pairDevice:
            GarminManager.shared.showDeviceSelection()
            return .nothing
        case .clearDevices:
            return .askConfirmation(title: "Clear All Devices?", message: "This will remove all paired Garmin devices from xDrip.", actionHandler: {
                GarminManager.shared.clearAllDevices()
            }, cancelHandler: nil)
        }
    }
    
    func isEnabled(index: Int) -> Bool { return true }
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool {
        return index == Setting.clearDevices.rawValue
    }
}
