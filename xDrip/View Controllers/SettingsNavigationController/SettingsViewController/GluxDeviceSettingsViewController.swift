import UIKit
#if canImport(ConnectIQ)
import ConnectIQ
#endif

final class GluxDeviceSettingsViewController: UIViewController {
    
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let deviceId: String
    private let deviceName: String
    
    // Exact colors from Main.storyboard for M5StackSettingsViewController
    private let m5StackTableBackgroundColor = UIColor(white: 0.1, alpha: 1.0)
    private let m5StackCellBackgroundColor = UIColor(white: 0.18, alpha: 1.0)
    private let m5StackDetailTextColor = UIColor(white: 0.67, alpha: 1.0)
    
    init(deviceId: String, deviceName: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = deviceName
        setupView()
        
        // Listen for status changes (handshakes, connections) from Garmin devices
        GarminManager.shared.onStatusChange = { [weak self] in
            self?.tableView.reloadData()
        }
        
        // Listen for sync results
        NotificationCenter.default.addObserver(self, selector: #selector(handleSyncResult(_:)), name: GarminManager.GarminSettingsSyncResult, object: nil)
        
        // Listen for handshakes (like pings)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHandshake(_:)), name: GarminManager.GarminHandshakeReceived, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        GarminManager.shared.onStatusChange = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHandshake(_ notification: Notification) {
        if let name = notification.userInfo?["deviceName"] as? String {
            SettingsViewUtilities.showToast(on: self, message: "✅ \(name) Responded")
        }
    }
    
    @objc private func handleSyncResult(_ notification: Notification) {
        guard let success = notification.userInfo?["success"] as? Bool,
              let id = notification.userInfo?["deviceId"] as? String,
              id == self.deviceId else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if success {
                SettingsViewUtilities.showToast(on: self, message: "☁️ Settings Synced")
            } else {
                let error = notification.userInfo?["error"] as? String ?? "Unknown"
                SettingsViewUtilities.showToast(on: self, message: "❌ Sync Failed: \(error)")
            }
        }
    }
    
    private func setupView() {
        view.backgroundColor = m5StackTableBackgroundColor
        setupTableView()
    }
    
    private func setupTableView() {
        tableView.backgroundColor = m5StackTableBackgroundColor
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .darkGray
        
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 40
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        tableView.dataSource = self
        tableView.delegate = self
    }
}

extension GluxDeviceSettingsViewController {
    private enum Section: Int, CaseIterable {
        case info
        case layout
        case preferences
        case actions
        
        func title() -> String? {
            switch self {
            case .info: return "Device Status"
            case .layout: return "Layout & Arragement"
            case .preferences: return "Preferences"
            case .actions: return "Actions"
            }
        }
    }
    
    private enum LayoutMode: String, CaseIterable {
        case bgTrend = "BA"
        case bgDelta = "BD"
        case timeDelta = "TD"
        case bgOnly = "B"
        case timeOnly = "T"
        case custom = "CUSTOM"
        
        var description: String {
            switch self {
            case .bgTrend: return "BG + Trend"
            case .bgDelta: return "BG + Delta"
            case .timeDelta: return "Time + Delta"
            case .bgOnly: return "BG Only"
            case .timeOnly: return "Time Only"
            case .custom: return "Custom..."
            }
        }
    }
}

extension GluxDeviceSettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = ConstantsUI.tableViewHeaderTextColor
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .layout:
            if indexPath.row == 0 { // Scaling Mode
                let modes = [
                    GarminManager.PriorityMode.none.description,
                    GarminManager.PriorityMode.l1.description,
                    GarminManager.PriorityMode.l2.description
                ]
                let current = GarminManager.shared.getPriorityMode(for: deviceId).rawValue
                
                SettingsViewUtilities.runSelectedRowAction(selectedRowAction: .selectFromList(title: "Select Scaling Mode", data: modes, selectedRow: current, actionTitle: "Select", cancelTitle: "Cancel", actionHandler: { [weak self] index in
                    guard let self = self, let mode = GarminManager.PriorityMode(rawValue: index) else { return }
                    GarminManager.shared.setPriorityMode(mode, for: self.deviceId)
                    self.tableView.reloadData()
                }, cancelHandler: nil, didSelectRowHandler: nil), forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: nil, tableView: tableView, forUIViewController: self)
            } else { // Line 1 or 2 arrangement
                let isLine1 = (indexPath.row == 1)
                let currentVal = isLine1 ? GarminManager.shared.getLine1Layout(for: deviceId) : GarminManager.shared.getLine2Layout(for: deviceId)
                
                var options = LayoutMode.allCases.map { $0.description }
                var selectedIdx = LayoutMode.allCases.firstIndex(where: { $0.rawValue == currentVal }) ?? (LayoutMode.allCases.count - 1)
                
                SettingsViewUtilities.runSelectedRowAction(selectedRowAction: .selectFromList(title: "Line \(isLine1 ? "1" : "2") Arrangement", data: options, selectedRow: selectedIdx, actionTitle: "Select", cancelTitle: "Cancel", actionHandler: { [weak self] index in
                    guard let self = self else { return }
                    let choice = LayoutMode.allCases[index]
                    if choice == .custom {
                        self.promptForCustomLayout(isLine1: isLine1)
                    } else {
                        if isLine1 {
                            GarminManager.shared.setLine1Layout(choice.rawValue, for: self.deviceId)
                        } else {
                            GarminManager.shared.setLine2Layout(choice.rawValue, for: self.deviceId)
                        }
                        self.tableView.reloadData()
                    }
                }, cancelHandler: nil, didSelectRowHandler: nil), forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: nil, tableView: tableView, forUIViewController: self)
            }
        case .preferences:
            if indexPath.row == 1 {
                let modes = [
                    GarminManager.TimerMode.off.description,
                    GarminManager.TimerMode.elapsed.description,
                    GarminManager.TimerMode.remaining.description
                ]
                let current = GarminManager.shared.getTimerMode(for: deviceId).rawValue
                
                SettingsViewUtilities.runSelectedRowAction(selectedRowAction: .selectFromList(title: "Select Timer Mode", data: modes, selectedRow: current, actionTitle: "Select", cancelTitle: "Cancel", actionHandler: { [weak self] index in
                    guard let self = self, let mode = GarminManager.TimerMode(rawValue: index) else { return }
                    GarminManager.shared.setTimerMode(mode, for: self.deviceId)
                    self.tableView.reloadData()
                }, cancelHandler: nil, didSelectRowHandler: nil), forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: nil, tableView: tableView, forUIViewController: self)
            }
        case .actions:
            #if canImport(ConnectIQ)
            if let device = GarminManager.shared.connectedDevices.first(where: { $0.uuid.uuidString == deviceId }) {
                GarminManager.shared.pingDevice(device)
            }
            #endif
        case .info:
            break
        }
    }
}

extension GluxDeviceSettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .info: return 1
        case .layout: return 3
        case .preferences: return 2
        case .actions: return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        
        let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: SettingsTableViewCell.reuseIdentifier)
        cell.backgroundColor = m5StackCellBackgroundColor
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = m5StackDetailTextColor
        cell.selectionStyle = .none
        
        switch section {
        case .info:
            cell.textLabel?.text = "Current Status"
            #if canImport(ConnectIQ)
            if let device = GarminManager.shared.connectedDevices.first(where: { $0.uuid.uuidString == deviceId }) {
                cell.detailTextLabel?.text = GarminManager.shared.deviceStatusString(for: device)
            }
            #endif
        case .preferences:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Record BG data to FIT"
                let toggle = UISwitch()
                toggle.isOn = GarminManager.shared.getRecordToFit(for: deviceId)
                toggle.addTarget(self, action: #selector(onRecordToFitToggle(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 1:
                cell.textLabel?.text = "Timer Mode"
                cell.detailTextLabel?.text = GarminManager.shared.getTimerMode(for: deviceId).description
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            default: break
            }
        case .layout:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Scaling Mode"
                cell.detailTextLabel?.text = GarminManager.shared.getPriorityMode(for: deviceId).description
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            case 1:
                cell.textLabel?.text = "Line 1 Group"
                let val = GarminManager.shared.getLine1Layout(for: deviceId)
                cell.detailTextLabel?.text = LayoutMode.allCases.first(where: { $0.rawValue == val })?.description ?? val
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            case 2:
                cell.textLabel?.text = "Line 2 Group"
                let val = GarminManager.shared.getLine2Layout(for: deviceId)
                cell.detailTextLabel?.text = LayoutMode.allCases.first(where: { $0.rawValue == val })?.description ?? val
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            default: break
            }
        case .actions:
            cell.textLabel?.text = "Send Test Ping"
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }
        
        return cell
    }
    
    @objc private func onRecordToFitToggle(_ sender: UISwitch) {
        GarminManager.shared.setRecordToFit(sender.isOn, for: deviceId)
    }
    
    private func promptForCustomLayout(isLine1: Bool) {
        let alert = UIAlertController(title: "Custom Arrangement", message: "Enter field codes in order:\nB: BG, A: Trend, D: Delta, T: Time\n(e.g. 'BA', 'BD', 'ATD')", preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.placeholder = "e.g. BA"
            textField.text = isLine1 ? GarminManager.shared.getLine1Layout(for: self?.deviceId ?? "") : GarminManager.shared.getLine2Layout(for: self?.deviceId ?? "")
            textField.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
            guard let self = self, let text = alert.textFields?.first?.text?.uppercased() else { return }
            if isLine1 {
                GarminManager.shared.setLine1Layout(text, for: self.deviceId)
            } else {
                GarminManager.shared.setLine2Layout(text, for: self.deviceId)
            }
            self.tableView.reloadData()
        }))
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title()
    }
}
