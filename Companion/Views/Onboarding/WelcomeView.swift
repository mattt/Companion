import SwiftUI

struct WelcomeView: View {
    let onAddServer: () -> Void
    let onAddExampleServer: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            // Heading
            VStack(spacing: 16) {
                AppIconImage(size: 80, cornerRadius: 16)
                
                VStack(spacing: 8) {
                    Text("Welcome to Companion")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Text("Get started by adding your first MCP server")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onAddServer) {
                    Label("Add Server...", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: onAddExampleServer) {
                    Label("Add Example Server", systemImage: "star.circle")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            
            // Callout
            HStack(spacing: 12) {
                Image("mcp.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("MCP servers provide tools, prompts, and resources to AI workflows")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.leading)
                    
                    Link(destination: URL(string: "https://huggingface.co/learn/mcp-course/en/unit0/introduction")!) {
                        HStack(spacing: 4) {
                            Text("Learn more about MCP")
                                .underline()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    .pointerStyle(.link)
                }
            }
            .padding(12)
            .background(.blue.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 1)
            )
            .clipped(antialiased: true)
            .padding(.top, 8)
        }
        .frame(maxWidth: 400)
        .padding()
    }
}

#Preview {
    WelcomeView(
        onAddServer: {},
        onAddExampleServer: {}
    )
        .frame(width: 600, height: 400)
}
