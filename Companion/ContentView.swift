import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private func createServerDetailStore(
        from store: StoreOf<AppFeature>, selection: SidebarSelection?, server: Server?
    ) -> StoreOf<ServerDetailFeature>? {
        guard let selection = selection,
            let server = server,
            selection.section == nil,  // Only for server selection, not sections
            let serverDetailState = store.serverDetails[id: server.id]
        else {
            return nil
        }

        return store.scope(
            state: { appState in appState.serverDetails[id: server.id] ?? serverDetailState },
            action: { .serverDetail(id: server.id, action: $0) }
        )
    }

    var body: some View {
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
        .task {
            store.send(.task)
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
