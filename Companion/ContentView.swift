import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showProgress = false

    private func createServerDetailStore(
        from store: StoreOf<AppFeature>, selection: SidebarSelection?, server: Server?
    ) -> StoreOf<ServerDetailFeature>? {
        guard let selection = selection,
            let server = server,
            selection.section == nil,  // Only for server selection, not sections
            let serverDetailState = store.serverDetails?[id: server.id]
        else {
            return nil
        }

        return store.scope(
            state: { appState in appState.serverDetails?[id: server.id] ?? serverDetailState },
            action: { .serverDetail(id: server.id, action: $0) }
        )
    }

    var body: some View {
        Group {
            if store.serverDetails == nil && showProgress {
                ProgressView("Loading servers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(showProgress ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: showProgress)
            } else if store.servers.isEmpty {
                WelcomeView(onAddServer: {
                    store.send(.presentAddServer)
                }, onAddExampleServer: {
                    store.send(.addExampleServer)
                })
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(store: store)
                        #if os(macOS)
                            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
                        #endif
                } detail: {
                    let selection = store.selection
                    let server = selection.flatMap { sel in
                        store.servers.first(where: { $0.id == sel.serverId })
                    }
                    DetailView(
                        selection: selection,
                        server: server,
                        store: createServerDetailStore(
                            from: store, selection: selection, server: server),
                        columnVisibility: columnVisibility
                    )
                    #if os(macOS)
                        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                    #endif
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .task {
            store.send(.task)
            
            // Delay showing progress to avoid flash
            try? await Task.sleep(for: .milliseconds(300))
            if store.serverDetails == nil {
                showProgress = true
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
        #if os(macOS)
            .frame(minWidth: 800, idealWidth: 1200, maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

}

#Preview {
    ContentView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
