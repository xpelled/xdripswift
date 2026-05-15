import UIKit

final class GluxSettingsViewController: UIViewController {
    
    private let tableView = UITableView(frame: .zero, style: .grouped)
    
    // Exact colors from Main.storyboard for M5StackSettingsViewController
    private let m5StackTableBackgroundColor = UIColor(white: 0.1, alpha: 1.0)
    private let m5StackCellBackgroundColor = UIColor(white: 0.18, alpha: 1.0)
    private let m5StackDetailTextColor = UIColor(white: 0.67, alpha: 1.0)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glux"
        setupView()
        
        // Listen for status changes (handshakes, connections) from Garmin devices
        GarminManager.shared.onStatusChange = { [weak self] in
            self?.tableView.reloadData()
        }
        
        // Listen for specific handshake responses for toasts
        NotificationCenter.default.addObserver(self, selector: #selector(handleHandshake(_:)), name: GarminManager.GarminHandshakeReceived, object: nil)
        
        // SYNC: Ping all known devices on entry to read their current settings
        let devices = GarminManager.shared.connectedDevices
        for device in devices {
            GarminManager.shared.pingDevice(device)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        GarminManager.shared.onStatusChange = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHandshake(_ notification: Notification) {
        if let deviceName = notification.userInfo?["deviceName"] as? String {
            showToast(message: "✅ \(deviceName) Responded")
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
    
    private func showToast(message: String) {
        let toastLabel = UILabel()
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.text = message
        toastLabel.alpha = 0.0
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        
        let padding: CGFloat = 20
        let labelHeight: CGFloat = 40
        let labelWidth = min(view.frame.width - 40, message.size(withAttributes: [.font: toastLabel.font!]).width + 40)
        
        toastLabel.frame = CGRect(x: (view.frame.width - labelWidth) / 2, y: view.frame.height - 120, width: labelWidth, height: labelHeight)
        
        view.addSubview(toastLabel)
        
        UIView.animate(withDuration: 0.3, animations: {
            toastLabel.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: .curveEaseOut, animations: {
                toastLabel.alpha = 0.0
            }) { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }
}

extension GluxSettingsViewController {
    private enum Section: Int, CaseIterable, SettingsProtocol {
        case devices
        case management
        
        func viewModel(coreDataManager: CoreDataManager?) -> SettingsViewModelProtocol {
            switch self {
            case .devices:
                return SettingsViewGluxDevicesViewModel()
            case .management:
                return SettingsViewGluxManagementViewModel()
            }
        }
    }
}

extension GluxSettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.textColor = ConstantsUI.tableViewHeaderTextColor
        }
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        if let footer = view as? UITableViewHeaderFooterView {
            footer.textLabel?.textColor = .lightGray
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        if section == .devices {
            let devices = GarminManager.shared.connectedDevices
            if indexPath.row < devices.count {
                let device = devices[indexPath.row]
                let detailVC = GluxDeviceSettingsViewController(deviceId: device.uuid.uuidString, deviceName: device.friendlyName ?? "Garmin")
                self.navigationController?.pushViewController(detailVC, animated: true)
                return
            }
        }
        
        let viewModel = section.viewModel(coreDataManager: nil)
        if viewModel.isEnabled(index: indexPath.row) {
            let action = viewModel.onRowSelect(index: indexPath.row)
            SettingsViewUtilities.runSelectedRowAction(selectedRowAction: action, forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withSettingsViewModel: viewModel, tableView: tableView, forUIViewController: self)
        }
    }
}

extension GluxSettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        return section.viewModel(coreDataManager: nil).numberOfRows()
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        let viewModel = section.viewModel(coreDataManager: nil)
        
        var cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.reuseIdentifier) as? SettingsTableViewCell
        if cell == nil {
            cell = SettingsTableViewCell(style: .value1, reuseIdentifier: SettingsTableViewCell.reuseIdentifier)
        }
        
        guard var validCell = cell else { return UITableViewCell() }
        
        SettingsViewUtilities.configureSettingsCell(cell: &validCell, forRowWithIndex: indexPath.row, forSectionWithIndex: indexPath.section, withViewModel: viewModel, tableView: tableView)
        
        validCell.backgroundColor = m5StackCellBackgroundColor
        validCell.textLabel?.textColor = .white
        validCell.detailTextLabel?.textColor = m5StackDetailTextColor
        
        return validCell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        return section.viewModel(coreDataManager: nil).sectionTitle()
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        return section.viewModel(coreDataManager: nil).sectionFooter()
    }
}
