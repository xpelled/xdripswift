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
    }
    
    private func setupView() {
        view.backgroundColor = m5StackTableBackgroundColor
        setupTableView()
    }
    
    private func setupTableView() {
        tableView.backgroundColor = m5StackTableBackgroundColor
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .darkGray
        
        // Use automatic dimension to allow headers/footers to grow with text
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
