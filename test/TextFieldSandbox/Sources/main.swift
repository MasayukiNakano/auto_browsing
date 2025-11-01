import SwiftUI

@main
struct TextFieldSandboxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}

struct ContentView: View {
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("テキストボックスのフォーカス確認用サンプル")
                .font(.headline)
            TextField("ここに入力してください", text: $input)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            Text("入力中の文字列: \(input)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 160, alignment: .leading)
    }
}
