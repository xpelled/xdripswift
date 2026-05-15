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
        case preferences
        case actions
        
        func title() -> String? {
            switch self {
            case .info: return "Device Status"
            case .preferences: return "Preferences"
            case .actions: return "Actions"
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
        
        if section == .preferences && indexPath.row == 4 {
            let modes = [
                GarminManager.PriorityMode.none.description,
                GarminManager.PriorityMode.bg.description,
                GarminManager.PriorityMode.bgTime.description,
                GarminManager.PriorityMode.bgDelta.description
            ]
            let current = GarminManager.shared.getPriorityMode(for: deviceId).rawValue
            
            SettingsViewUtilities.runSelectedRowAction(selectedRowAction: .selectFromList(title: "Select Priority Mode", data: modes, selectedRow: current, actionTitle: "Select", cancelTitle: "Cancel", actionHandler: { [weak self] index in
                guard let self = self, let mode = GarminManager.PriorityMode(rawValue: index) else { return }
                GarminManager.shared.setPriorityMode(mode, for: self.deviceId)
            }, cancelHandler: nil, didSelectRowHandler: nil), forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: nil, tableView: tableView, forUIViewController: self)
        } else if section == .preferences && indexPath.row == 2 {
            let modes = [
                GarminManager.TimerMode.off.description,
                GarminManager.TimerMode.elapsed.description,
                GarminManager.TimerMode.remaining.description
            ]
            let current = GarminManager.shared.getTimerMode(for: deviceId).rawValue
            
            SettingsViewUtilities.runSelectedRowAction(selectedRowAction: .selectFromList(title: "Select Timer Mode", data: modes, selectedRow: current, actionTitle: "Select", cancelTitle: "Cancel", actionHandler: { [weak self] index in
                guard let self = self, let mode = GarminManager.TimerMode(rawValue: index) else { return }
                GarminManager.shared.setTimerMode(mode, for: self.deviceId)
            }, cancelHandler: nil, didSelectRowHandler: nil), forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: nil, tableView: tableView, forUIViewController: self)
        } else if section == .actions {
            #if canImport(ConnectIQ)
            if let device = GarminManager.shared.connectedDevices.first(where: { $0.uuid.uuidString == deviceId }) {
                GarminManager.shared.pingDevice(device)
            }
            #endif
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
        case .preferences: return 5
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
                cell.textLabel?.text = "Display Trend Arrow"
                let toggle = UISwitch()
                toggle.isOn = GarminManager.shared.getShowArrow(for: deviceId)
                toggle.addTarget(self, action: #selector(onShowArrowToggle(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 1:
                cell.textLabel?.text = "Record BG data to FIT"
                let toggle = UISwitch()
                toggle.isOn = GarminManager.shared.getRecordToFit(for: deviceId)
                toggle.addTarget(self, action: #selector(onRecordToFitToggle(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 2:
                cell.textLabel?.text = "Timer Mode"
                cell.detailTextLabel?.text = GarminManager.shared.getTimerMode(for: deviceId).description
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            case 3:
                cell.textLabel?.text = "Show Delta"
                let toggle = UISwitch()
                toggle.isOn = GarminManager.shared.getShowDelta(for: deviceId)
                toggle.addTarget(self, action: #selector(onShowDeltaToggle(_:)), for: .valueChanged)
                cell.accessoryView = toggle
            case 4:
                cell.textLabel?.text = "Priority Mode"
                cell.detailTextLabel?.text = GarminManager.shared.getPriorityMode(for: deviceId).description
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
    
    @objc private func onShowArrowToggle(_ sender: UISwitch) {
        GarminManager.shared.setShowArrow(sender.isOn, for: deviceId)
    }
    
    @objc private func onRecordToFitToggle(_ sender: UISwitch) {
        GarminManager.shared.setRecordToFit(sender.isOn, for: deviceId)
    }
    
    @objc private func onShowDeltaToggle(_ sender: UISwitch) {
        GarminManager.shared.setShowDelta(sender.isOn, for: deviceId)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title()
    }
}
