import ComposableArchitecture
import MCP
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<AppFeature>
    @FocusState private var isFocused: Bool

    @State private var expandedServers: Set<String> = []

    // Extract selection binding as a computed property
    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { store.selection },
            set: { store.send(.selectionChanged($0)) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            let sidebarItems = buildSidebarItems(from: store.serverDetails)

            List(selection: selectionBinding) {
                listContent(items: sidebarItems)
            }
            #if os(macOS)
                .listStyle(.sidebar)
                .padding(.bottom, 8)
            #else
                .listStyle(.insetGrouped)
            #endif
        }
        .navigationTitle("Servers")
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { store.send(.presentAddServer) }) {
                    Label("Add Server", systemImage: "plus")
                }
            }
        }
        .sheet(
            store: store.scope(state: \.$addServer, action: \.addServerPresentation)
        ) { addServerStore in
            AddServerSheet(
                isPresented: .constant(true),
                onAdd: { name, transport in
                    addServerStore.send(.addServer(name: name, transport: transport))
                },
                onCancel: { addServerStore.send(.dismiss) }
            )
        }
        .sheet(
            store: store.scope(state: \.$editServer, action: \.editServer)
        ) { editServerStore in
            EditServerSheet(
                isPresented: .constant(true),
                server: editServerStore.server,
                onSave: { name, transport in
                    editServerStore.send(.updateServer(name: name, transport: transport))
                },
                onCancel: { editServerStore.send(.dismiss) },
                store: editServerStore)
        }
    }

    // Extract list content into a separate function
    @ViewBuilder
    private func listContent(items: [SidebarItem]) -> some View {
        #if os(macOS)
            macOSListContent(items: items)
        #else
            iOSListContent(items: items)
        #endif
    }

    // Separate iOS list content
    @ViewBuilder
    private func iOSListContent(items: [SidebarItem]) -> some View {
        ForEach(items, id: \.id) { sidebarItem in
            if case .server(let server) = sidebarItem {
                Section {
                    if let serverDetail = store.serverDetails[id: server.id],
                        serverDetail.isConnected
                    {
                        if expandedServers.contains(server.id) {
                            serverInfoRow(server: server)
                        }
                    } else {
                        connectionPromptRow(server: server)
                    }

                    if expandedServers.contains(server.id), let children = sidebarItem.children {
                        ForEach(children, id: \.id) { child in
                            childRow(child: child)
                        }
                    }
                } header: {
                    sidebarServerHeader(for: server)
                }
            }
        }
        .onAppear {
            initializeExpandedServers(from: items)
        }
    }

    // Separate macOS list content
    @ViewBuilder
    private func macOSListContent(items: [SidebarItem]) -> some View {
        ForEach(items, id: \.id) { sidebarItem in
            if case .server(let server) = sidebarItem {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedServers.contains(server.id) },
                        set: { isExpanded in
                            toggleServerExpansion(server.id, isExpanded: isExpanded)
                        }
                    )
                ) {
                    if let children = sidebarItem.children {
                        ForEach(children, id: \.id) { child in
                            childRow(child: child)
                        }
                    }
                } label: {
                    serverRow(sidebarItem: sidebarItem)
                }
            }
        }
        .onAppear {
            initializeExpandedServers(from: items)
        }
    }

    // Helper function for connection prompt row
    @ViewBuilder
    private func connectionPromptRow(server: Server) -> some View {
        Button {
            if let serverDetail = store.serverDetails[id: server.id] {
                if serverDetail.isConnecting {
                    store.send(.serverDetail(id: server.id, action: .cancel))
                } else {
                    store.send(.serverDetail(id: server.id, action: .connect))
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let serverDetail = store.serverDetails[id: server.id],
                    serverDetail.isConnecting
                {
                    ProgressView()
                        .scaleEffect(0.8)
                        #if os(macOS)
                            .frame(width: 18)
                        #else
                            .frame(width: 22)
                        #endif
                } else {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.accentColor)
                        #if os(macOS)
                            .font(.system(size: 14))
                            .frame(width: 18)
                        #else
                            .font(.system(size: 16))
                            .frame(width: 22)
                        #endif
                }

                Text(
                    store.serverDetails[id: server.id]?.isConnecting == true
                        ? "Connecting..."
                        : "Connect to Server"
                )
                #if os(macOS)
                    .font(.system(size: 13))
                #else
                    .font(.system(size: 15))
                #endif
                .foregroundColor(.accentColor)

                Spacer()
            }
            #if os(macOS)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            #elseif os(visionOS)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            #else
                .padding(.vertical, 11)
                .padding(.horizontal, 0)
            #endif
            #if os(visionOS)
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16))
            #else
                .contentShape(Rectangle())
            #endif
        }
        .buttonStyle(.plain)
        #if !os(macOS)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
        #endif
    }

    // Helper function for server info row
    @ViewBuilder
    private func serverInfoRow(server: Server) -> some View {
        if let tag = selection(for: .server(server)) {
            serverInformationRow(for: server)
                .tag(tag)
                #if !os(macOS)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                #endif
        } else {
            serverInformationRow(for: server)
                #if !os(macOS)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                #endif
        }
    }

    // Helper function for child rows
    @ViewBuilder
    private func childRow(child: SidebarItem) -> some View {
        if let tag = selection(for: child) {
            sidebarRow(for: child)
                .tag(tag)
                #if !os(macOS)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                #endif
        } else {
            sidebarRow(for: child)
                #if !os(macOS)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                #endif
        }
    }

    // Helper function for server rows
    @ViewBuilder
    private func serverRow(sidebarItem: SidebarItem) -> some View {
        if case .server(let server) = sidebarItem {
            if let tag = selection(for: .server(server)) {
                sidebarRow(for: sidebarItem)
                    .tag(tag)
            } else {
                sidebarRow(for: sidebarItem)
            }
        }
    }

    // Helper function to initialize expanded servers
    private func initializeExpandedServers(from items: [SidebarItem]) {
        for item in items {
            if case .server(let server) = item {
                expandedServers.insert(server.id)
            }
        }
    }

    private func buildSidebarItems(from serverDetails: IdentifiedArrayOf<ServerDetailFeature.State>)
        -> [SidebarItem]
    {
        return serverDetails.map { serverDetail in
            return .server(serverDetail.server)
        }
    }

    private func toggleServerExpansion(_ serverId: String, isExpanded: Bool) {
        if isExpanded {
            expandedServers.insert(serverId)
        } else {
            expandedServers.remove(serverId)
        }
    }

    @ViewBuilder
    private func sidebarRow(for sidebarItem: SidebarItem) -> some View {
        HStack(spacing: 12) {
            icon(for: sidebarItem)
                .foregroundColor(.accentColor)
                #if os(macOS)
                    .font(.system(size: 14))
                    .frame(width: 18)
                #else
                    .font(.system(size: 16))
                    .frame(width: 22)
                #endif

            Text(sidebarItem.name)
                #if os(macOS)
                    .font(.system(size: 13))
                #else
                    .font(.system(size: 15))
                #endif
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // Right-side elements
            HStack(spacing: 4) {
                // Add connection status indicator for server items
                if case .server(let server) = sidebarItem,
                    let serverDetail = store.serverDetails[id: server.id]
                {
                    #if os(macOS)
                        ConnectionButton(
                            isConnected: serverDetail.isConnected,
                            isConnecting: serverDetail.isConnecting,
                            action: {
                                if serverDetail.isConnected {
                                    store.send(.serverDetail(id: server.id, action: .disconnect))
                                } else if serverDetail.isConnecting {
                                    store.send(.serverDetail(id: server.id, action: .cancel))
                                } else {
                                    store.send(.serverDetail(id: server.id, action: .connect))
                                }
                            }
                        )
                    #else
                        // Skip connection button in rows on iOS, handled in header
                    #endif
                }

                if let badge = collectionBadge(for: sidebarItem) {
                    Text(badge)
                        #if os(macOS)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                            )
                        #else
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                        #endif
                }
            }
        }
        #if os(macOS)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        #elseif os(visionOS)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        #else
            .padding(.vertical, 11)
            .padding(.horizontal, 0)
        #endif
        #if os(visionOS)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.03))
            )
        #else
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.0))
            )
        #endif

        .contextMenu {
            if case .server(let server) = sidebarItem {
                if let serverDetail = store.serverDetails[id: server.id] {
                    if serverDetail.isConnected {
                        Button("Disconnect") {
                            store.send(.serverDetail(id: server.id, action: .disconnect))
                        }
                    } else {
                        Button("Connect") {
                            store.send(.serverDetail(id: server.id, action: .connect))
                        }
                    }

                    Divider()
                    Button("Edit Server") {
                        store.send(.presentEditServer(server))
                    }
                    Button("Refresh") {
                        store.send(.serverDetail(id: server.id, action: .refresh))
                    }
                    Divider()
                    Button("Remove Server", role: .destructive) {
                        store.send(.removeServer(id: server.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarServerHeader(for server: Server) -> some View {
        #if os(macOS)
            Button {
                store.send(.selectionChanged(.server(server)))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Show connection status
                        if let serverDetail = store.serverDetails[id: server.id] {
                            ServerConnectionStatusView(
                                serverId: server.id,
                                status: serverDetail.serverStatus,
                                isConnecting: serverDetail.isConnecting,
                                isLoadingData: serverDetail.isLoadingData,
                                onConnect: {
                                    store.send(.serverDetail(id: server.id, action: .connect))
                                },
                                onDisconnect: {
                                    store.send(.serverDetail(id: server.id, action: .disconnect))
                                },
                                onCancel: {
                                    store.send(.serverDetail(id: server.id, action: .cancel))
                                }
                            )
                        }
                    }

                    Spacer()

                    Button(action: {
                        store.send(.serverDetail(id: server.id, action: .refresh))
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #if os(visionOS)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                #else
                    .padding(.vertical, 8)
                #endif
                #if os(visionOS)
                    .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16))
                #else
                    .contentShape(Rectangle())
                #endif
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let serverDetail = store.serverDetails[id: server.id] {
                    if serverDetail.isConnected {
                        Button("Disconnect") {
                            store.send(.serverDetail(id: server.id, action: .disconnect))
                        }
                    } else {
                        Button("Connect") {
                            store.send(.serverDetail(id: server.id, action: .connect))
                        }
                    }

                    Divider()
                    Button("Edit Server") {
                        store.send(.presentEditServer(server))
                    }
                    Button("Refresh") {
                        store.send(.serverDetail(id: server.id, action: .refresh))
                    }
                    Divider()
                    Button("Remove Server", role: .destructive) {
                        store.send(.removeServer(id: server.id))
                    }
                }
            }
        #else
            Button(action: {
                if expandedServers.contains(server.id) {
                    expandedServers.remove(server.id)
                } else {
                    expandedServers.insert(server.id)
                }
            }) {
                HStack(spacing: 0) {
                    Text(server.name.localizedUppercase)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    if let serverDetail = store.serverDetails[id: server.id],
                        serverDetail.isConnected
                    {
                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.7))
                            .rotationEffect(.degrees(expandedServers.contains(server.id) ? 90 : 0))
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.7),
                                value: expandedServers.contains(server.id))
                    }
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 8)
                #if os(visionOS)
                    .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16))
                #else
                    .contentShape(Rectangle())
                #endif
            }
            .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func serverInformationRow(for server: Server) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundColor(.accentColor)
                #if os(macOS)
                    .font(.system(size: 14))
                    .frame(width: 18)
                #else
                    .font(.system(size: 16))
                    .frame(width: 22)
                #endif

            Text("Server Information")
                #if os(macOS)
                    .font(.system(size: 13))
                #else
                    .font(.system(size: 15))
                #endif
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        #if os(macOS)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        #elseif os(visionOS)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        #else
            .padding(.vertical, 11)
            .padding(.horizontal, 0)
        #endif
        #if os(visionOS)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.03))
            )
        #else
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.0))
            )
        #endif
        .contextMenu {
            if let serverDetail = store.serverDetails[id: server.id] {
                if serverDetail.isConnected {
                    Button("Disconnect") {
                        store.send(.serverDetail(id: server.id, action: .disconnect))
                    }
                } else {
                    Button("Connect") {
                        store.send(.serverDetail(id: server.id, action: .connect))
                    }
                }

                Divider()
                Button("Edit Server") {
                    store.send(.presentEditServer(server))
                }
                Button("Refresh") {
                    store.send(.serverDetail(id: server.id, action: .refresh))
                }
                Divider()
                Button("Remove Server", role: .destructive) {
                    store.send(.removeServer(id: server.id))
                }
            }
        }
    }

    private func icon(for item: SidebarItem) -> Image {
        switch item {
        case .server(let server):
            switch server.configuration.transportType {
            case .http:
                return Image(systemName: "cloud")
            case .stdio:
                return Image(systemName: "apple.terminal")
            }
        case .prompts:
            return Image(systemName: "text.bubble")
        case .resources:
            return Image(systemName: "doc.text")
        case .tools:
            return Image(systemName: "wrench.and.screwdriver")
        default:
            return Image(systemName: "questionmark.circle")
        }
    }

    private func collectionBadge(for item: SidebarItem) -> String? {
        switch item {
        case .prompts(_, let prompts):
            return "\(prompts.count)"
        case .resources(_, let resources, let templates):
            return "\(resources.count + templates.count)"
        case .tools(_, let tools):
            return "\(tools.count)"
        default:
            return nil
        }
    }

    private func selection(for item: SidebarItem) -> SidebarSelection? {
        switch item {
        case .server(let server):
            return .server(server)
        case .prompts(let serverId, _):
            return .prompts(serverId: serverId)
        case .resources(let serverId, _, _):
            return .resources(serverId: serverId)
        case .tools(let serverId, _):
            return .tools(serverId: serverId)
        default:
            return nil
        }
    }

}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select an item")
                .font(.title2)
                .fontWeight(.medium)

            Text("Choose a server, prompt, resource, or tool from the sidebar to view its details")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct ServerConnectionStatusView: View {
    let serverId: String
    let status: Server.Status
    let isConnecting: Bool
    let isLoadingData: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
                .font(.system(size: 10))
                .foregroundColor(statusColor)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if status.isConnected && !isLoadingData {
                Button(action: onDisconnect) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            } else if isConnecting {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            } else if !status.isConnected {
                Button(action: onConnect) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var statusIcon: Image {
        if isConnecting {
            return Image(systemName: "bolt.badge.clock.fill")
        } else if isLoadingData {
            return Image(systemName: "arrow.clockwise.circle")
        } else {
            switch status {
            case .connected:
                return Image(systemName: "bolt.fill")
            case .disconnected:
                return Image(systemName: "bolt")
            case .connecting:
                return Image(systemName: "bolt.badge.clock.fill")
            case .error:
                return Image(systemName: "exclamationmark.triangle.fill")
            }
        }
    }

    private var statusColor: Color {
        if isConnecting || isLoadingData {
            return .orange
        } else {
            switch status {
            case .connected:
                return .green
            case .disconnected:
                return .red
            case .connecting:
                return .orange
            case .error:
                return .red
            }
        }
    }

    private var statusText: String {
        if isConnecting {
            return "Connecting..."
        } else if isLoadingData {
            return "Loading..."
        } else {
            return status.displayText
        }
    }
}

struct ConnectionButton: View {
    let isConnected: Bool
    let isConnecting: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isConnecting {
                    Image(systemName: isHovered ? "xmark.circle.fill" : "bolt.badge.clock.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            isHovered ? Color.red : Color.orange,
                            Color.secondary
                        )
                } else if isConnected {
                    Image(systemName: isHovered ? "bolt.slash" : "bolt.fill")
                        .foregroundColor(isHovered ? .red : .accentColor)
                } else {
                    Image(systemName: "bolt")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(
                        isHovered
                            ? (isConnecting
                                ? Color.red.opacity(0.15)
                                : Color.secondary.opacity(0.15))
                            : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Circle())
        .help(helpText)
    }

    private var helpText: String {
        if isConnecting {
            return "Cancel connection"
        } else if isConnected {
            return "Disconnect server"
        } else {
            return "Connect server"
        }
    }
}
