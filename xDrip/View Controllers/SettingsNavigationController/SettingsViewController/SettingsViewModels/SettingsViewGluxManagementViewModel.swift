import UIKit

fileprivate enum Setting: Int, CaseIterable {
    case pairDevice = 0
    case clearDevices = 1
    case showArrow = 2
    case recordToFit = 3
}

class SettingsViewGluxManagementViewModel: NSObject, SettingsViewModelProtocol {
    private var rowReloadClosure: ((Int) -> Void)?
    
    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {
        self.rowReloadClosure = rowReloadClosure
    }
    func storeUIViewController(uIViewController: UIViewController) {}
    func storeMessageHandler(messageHandler: @escaping ((String, String) -> Void)) {}
    
    func sectionTitle() -> String? {
        return "Management & Preferences"
    }
    
    func sectionFooter() -> String? {
        return "Use 'Pair' to find new devices via Garmin Connect. 'Display Arrow' toggles the trend arrow on the watch. 'Record to FIT' saves glucose data into your Garmin activity files."
    }
    
    func settingsRowText(index: Int) -> String {
        guard let setting = Setting(rawValue: index) else { return "" }
        switch setting {
        case .pairDevice: return "Pair New Garmin Device"
        case .clearDevices: return "Clear All Paired Devices"
        case .showArrow: return "Display Trend Arrow"
        case .recordToFit: return "Record BG data to FIT"
        }
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        return (index == 0) ? .disclosureIndicator : .none
    }
    
    func detailedText(index: Int) -> String? {
        return nil
    }
    
    func uiView(index: Int) -> UIView? {
        guard let setting = Setting(rawValue: index) else { return nil }
        
        if setting == .showArrow || setting == .recordToFit {
            let toggle = UISwitch()
            toggle.onTintColor = ConstantsUI.switchOnTintColor
            
            if setting == .showArrow {
                toggle.isOn = GarminManager.shared.showArrow
                toggle.addTarget(self, action: #selector(onShowArrowToggle(_:)), for: .valueChanged)
            } else if setting == .recordToFit {
                toggle.isOn = GarminManager.shared.recordToFit
                toggle.addTarget(self, action: #selector(onRecordToFitToggle(_:)), for: .valueChanged)
            }
            return toggle
        }
        
        return nil
    }
    
    @objc private func onShowArrowToggle(_ sender: UISwitch) {
        GarminManager.shared.showArrow = sender.isOn
    }
    
    @objc private func onRecordToFitToggle(_ sender: UISwitch) {
        GarminManager.shared.recordToFit = sender.isOn
    }
    
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
        case .showArrow, .recordToFit:
            return .nothing // Handled by UISwitch
        }
    }
    
    func isEnabled(index: Int) -> Bool { return true }
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool { return false }
}
