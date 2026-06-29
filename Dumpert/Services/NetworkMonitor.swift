import Foundation
import Network

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "nl.dumpert.tvos.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                // Only .satisfied means the path is actually usable. .requiresConnection
                // is a not-yet-up path (e.g. on-demand VPN/cellular) and must not read
                // as online, or the offline banner hides while requests still fail.
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
