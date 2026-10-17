import SwiftUI

struct ContentView: View {
    @Environment(ServerStore.self) private var store
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var store = store

        Group {
            if store.servers.isEmpty {
                WelcomeView(
                    onAddServer: { store.presentAddServer() },
                    onAddExampleServer: { store.addExampleServer() }
                )
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                        #if os(macOS)
                            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
                        #endif
                } detail: {
                    let selection = store.selection
                    let server = selection.flatMap { store.server(id: $0.serverId) }
                    DetailView(
                        selection: selection,
                        server: server,
                        columnVisibility: columnVisibility
                    )
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .addServer:
                AddServerSheet(
                    isPresented: .constant(true),
                    onAdd: { name, transport in
                        store.addServer(name: name, configuration: transport)
                        store.sheet = nil
                    },
                    onCancel: { store.sheet = nil }
                )
            case .editServer(let server):
                EditServerSheet(
                    isPresented: .constant(true),
                    server: server,
                    onSave: { name, transport in
                        store.updateServer(id: server.id, name: name, configuration: transport)
                        store.sheet = nil
                    },
                    onCancel: { store.sheet = nil }
                )
            }
        }
        #if os(macOS)
            .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#Preview {
    ContentView()
        .environment(ServerStore())
}
