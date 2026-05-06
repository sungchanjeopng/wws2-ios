// Ported from app/src/main/java/com/wws2/densitymeter/ui/screen/ChatbotScreen.kt
//
// The Android version is 962 lines and includes:
//   - The chat UI (header, language/product selectors, message list, input bar)
//   - OpenAI Chat Completions HTTP client with embedding-driven RAG retrieval
//     against three on-device JSON corpora (rag_density / rag_interface /
//     rag_interface_120) loaded from android assets/.
//
// This port covers the chat UI faithfully and stubs the OpenAI + RAG layer
// behind a single sendQuestion() function that returns a placeholder
// response. Wiring in URLSession-based HTTP + a small cosine-similarity
// retriever over a Bundle-loaded JSON corpus is straightforward and lands
// in a follow-up commit.

import SwiftUI
import WWS2Core

private let chatbotProducts = ["ENV200", "ENV130", "ENV120"]

private struct LangConfig {
    let greeting: String
    let placeholder: String
    let langRule: String
    let unknown: String
}

private let chatbotLanguages: [(name: String, config: LangConfig)] = [
    ("English", LangConfig(
        greeting: "Hello!",
        placeholder: "Type your question...",
        langRule: "You must answer only in English. Keep product names and model names as-is.",
        unknown: "The requested information could not be found. Please contact support at 041-584-8820."
    )),
    ("Korean", LangConfig(
        greeting: "안녕하세요! 제품에 대해 궁금한 점을 물어보세요.",
        placeholder: "질문을 입력하세요...",
        langRule: "반드시 한국어로만 답변하세요. 제품명, 모델명 등 고유명사만 영어 그대로 사용하세요.",
        unknown: "해당 정보는 확인되지 않습니다. 추가 문의는 고객지원(041-584-8820)으로 연락해주세요."
    )),
    ("Japanese", LangConfig(
        greeting: "こんにちは！製品についてお気軽にご質問ください。",
        placeholder: "質問を入力してください...",
        langRule: "必ず日本語のみで回答してください。製品名・モデル名はそのまま英語で使用してください。",
        unknown: "該当情報は確認できませんでした。詳細はサポート(041-584-8820)までお問い合わせください。"
    )),
    ("Chinese", LangConfig(
        greeting: "您好！欢迎咨询产品相关问题。",
        placeholder: "请输入您的问题...",
        langRule: "必须仅用中文回答。产品名称和型号保持英文原样。",
        unknown: "未找到相关信息。如需进一步咨询，请联系客服(041-584-8820)。"
    )),
    ("Spanish", LangConfig(
        greeting: "Hola! Pregunteme sobre los productos.",
        placeholder: "Escriba su pregunta...",
        langRule: "Debes responder solo en espanol. Manten los nombres de productos y modelos en su forma original.",
        unknown: "No se encontro la informacion solicitada. Contacte al soporte al 041-584-8820."
    )),
    ("German", LangConfig(
        greeting: "Hallo! Fragen Sie mich zu den Produkten.",
        placeholder: "Geben Sie Ihre Frage ein...",
        langRule: "Sie muessen ausschliesslich auf Deutsch antworten. Produkt- und Modellnamen bleiben in der Originalform (Englisch).",
        unknown: "Die angeforderten Informationen konnten nicht gefunden werden. Bitte wenden Sie sich an den Support unter 041-584-8820."
    )),
]

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" | "assistant"
    let content: String
}

public struct ChatbotScreen: View {
    @ObservedObject var vm: AppViewModel

    @State private var selectedProduct: String = chatbotProducts[0]
    @State private var selectedLang: String = "English"
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isLoading: Bool = false

    public init(vm: AppViewModel) {
        self.vm = vm
        _messages = State(initialValue: [
            ChatMessage(role: "assistant",
                        content: chatbotLanguages.first?.config.greeting ?? "Hello!")
        ])
    }

    private var langConfig: LangConfig {
        chatbotLanguages.first(where: { $0.name == selectedLang })?.config
            ?? chatbotLanguages[0].config
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Product / Language pickers
            HStack(spacing: 8) {
                Picker("Product", selection: $selectedProduct) {
                    ForEach(chatbotProducts, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))

                Picker("Language", selection: $selectedLang) {
                    ForEach(chatbotLanguages, id: \.name) { Text($0.name).tag($0.name) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.white)
            .onChange(of: selectedProduct) { _, _ in resetGreeting() }
            .onChange(of: selectedLang) { _, _ in resetGreeting() }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in ChatBubble(msg: msg).id(msg.id) }
                        if isLoading {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Generating...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.grayLabel)
                            }
                            .padding(.leading, 8)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            // Input bar
            HStack(alignment: .center, spacing: 8) {
                TextField(langConfig.placeholder, text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.lightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColors.border))
                    .lineLimit(1...4)

                Button(action: sendCurrentInput) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(canSend ? Color.white : AppColors.grayLabel)
                        .frame(width: 44, height: 44)
                        .background(
                            Group {
                                if canSend {
                                    LinearGradient(
                                        colors: [Color(hex: 0x3182F6), Color(hex: 0x7C3AED)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                } else {
                                    AppColors.lightGray
                                }
                            }
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.white)
        }
        .background(AppColors.background)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private func resetGreeting() {
        messages = [ChatMessage(role: "assistant", content: langConfig.greeting)]
    }

    private func sendCurrentInput() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }
        input = ""
        messages.append(ChatMessage(role: "user", content: question))
        isLoading = true

        Task { @MainActor in
            // TODO: port the OpenAI Chat Completions + RAG cosine-similarity flow
            // from ChatbotScreen.kt:loadRagData / cosineSimilarity / searchSimilar /
            // callOpenAIWithRAG. For now we surface a clear placeholder so the
            // chat UI is fully exercisable end-to-end.
            try? await Task.sleep(nanoseconds: 400_000_000)
            let placeholder = """
[OpenAI integration TODO — UI shell ported, network/RAG layer pending]
Question received: "\(question)"
Product: \(selectedProduct), Language: \(selectedLang)
"""
            messages.append(ChatMessage(role: "assistant", content: placeholder))
            isLoading = false
        }
    }
}

private struct ChatBubble: View {
    let msg: ChatMessage
    var body: some View {
        let isUser = msg.role == "user"
        HStack {
            if isUser { Spacer() }
            Text(msg.content)
                .font(.system(size: 15))
                .foregroundStyle(isUser ? Color.white : AppColors.darkText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isUser {
                            LinearGradient(
                                colors: [Color(hex: 0x3182F6), Color(hex: 0x7C3AED)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        } else {
                            AppColors.white
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isUser ? Color.clear : AppColors.border, lineWidth: 1)
                )
                .shadow(color: AppColors.cardShadow, radius: 1, y: 1)
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer() }
        }
    }
}
