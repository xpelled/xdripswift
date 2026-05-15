import UIKit

class SettingsViewGarminSettingsViewModel: NSObject, SettingsViewModelProtocol {
    private var uIViewController: UIViewController?
    private var messageHandler: ((String, String) -> Void)?
    
    func storeRowReloadClosure(rowReloadClosure: @escaping ((Int) -> Void)) {}
    
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
        return nil
    }
    
    func settingsRowText(index: Int) -> String {
        return "Glux"
    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        return .disclosureIndicator
    }
    
    func detailedText(index: Int) -> String? {
        let count = GarminManager.shared.connectedDevices.count
        if count == 0 {
            return "Not Configured"
        } else {
            return "\(count) Device\(count == 1 ? "" : "s") paired"
        }
    }
    
    func uiView(index: Int) -> UIView? {
        return nil
    }
    
    func numberOfRows() -> Int {
        return 1
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        return .callFunction { [weak self] in
            let vc = GluxSettingsViewController()
            // No need to configure with a VM anymore, the VC handles its own sections internally now.
            self?.uIViewController?.navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    func isEnabled(index: Int) -> Bool {
        return true
    }
    
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool {
        return false
    }
}
