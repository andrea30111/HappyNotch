import SwiftUI

/// Optional full-window dashboard (also the main UI fallback for people who prefer a window).
struct DashboardView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, selection: $state.dashboardTool) { tool in
                Label(tool.title, systemImage: tool.symbol)
                    .tag(tool)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            ToolContentView(tool: state.dashboardTool ?? .workspace)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .navigationTitle((state.dashboardTool ?? .workspace).title)
                .toolbar {
                    let tool = state.dashboardTool ?? .workspace
                    if tool.canBeOnDashboard {
                        Menu {
                            DashboardMenuItems(tool: tool)
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
