import SwiftUI
import AppKit

/// Avisos: o banner no topo, disparado pelo painel do BispoTvApi
/// (/painel/avisos), sem versão nova do app. Pede ao abrir e de 5 em 5
/// minutos; os que a pessoa fechou ficam guardados no Mac. Em tela cheia, só
/// o urgente aparece.
@MainActor
final class Avisos: ObservableObject {
    static let shared = Avisos()

    struct Aviso: Decodable, Identifiable, Equatable {
        struct Link: Decodable, Equatable { let url: String; let texto: String }
        let id: Int
        let tipo: String
        let texto: String
        let link: Link?
        let fechavel: Bool
    }

    @Published private(set) var todos: [Aviso] = []
    @Published private(set) var fechados: Set<Int>
    @Published private(set) var telaCheia = false

    private let chaveFechados = "avisos.fechados"
    private var relogio: Timer?

    private init() {
        fechados = Set(UserDefaults.standard.array(forKey: chaveFechados) as? [Int] ?? [])
        for (nome, cheia) in [(NSWindow.didEnterFullScreenNotification, true), (NSWindow.didExitFullScreenNotification, false)] {
            NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.telaCheia = cheia }
            }
        }
    }

    /// O que mostrar agora: sem os fechados; em tela cheia, só o urgente.
    var visiveis: [Aviso] {
        todos.filter { !($0.fechavel && fechados.contains($0.id)) && (!telaCheia || $0.tipo == "urgente") }
    }

    func iniciar() {
        guard relogio == nil else { return }
        Task { await atualizar() }
        relogio = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.atualizar() }
        }
    }

    func atualizar() async {
        guard let token = Conta.shared.tokenAtual else { todos = []; return }
        var componentes = URLComponents(url: Conta.api.appendingPathComponent("avisos"), resolvingAgainstBaseURL: false)!
        componentes.queryItems = [URLQueryItem(name: "plataforma", value: "mac")]
        var pedido = URLRequest(url: componentes.url!)
        pedido.timeoutInterval = 20
        pedido.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        struct Resposta: Decodable { let avisos: [Aviso] }
        guard let (dados, r) = try? await URLSession.shared.data(for: pedido),
              (r as? HTTPURLResponse)?.statusCode == 200,
              let lista = try? JSONDecoder().decode(Resposta.self, from: dados) else { return }
        todos = lista.avisos
    }

    func fechar(_ aviso: Aviso) {
        fechados.insert(aviso.id)
        UserDefaults.standard.set(Array(fechados.suffix(200)), forKey: chaveFechados)
    }

    /// O link do "ligar WhatsApp" gera o código aqui mesmo e abre a conversa.
    func abrir(_ link: Aviso.Link) {
        if link.url == "https://bispotv.pages.dev/vincular" {
            Task { try? await Conta.shared.ligarWhatsapp() }
        } else if let url = URL(string: link.url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// As mesmas cores nos cinco apps (BispoTvApi/src/avisos.mjs).
    static func cores(_ tipo: String) -> (cor: Color, fundo: Color) {
        switch tipo {
        case "novidade": return (Color(hex: 0x5BC88A), Color(hex: 0x294340))
        case "atencao": return (Color(hex: 0xE8B54A), Color(hex: 0x483E32))
        case "urgente": return (Color(hex: 0xE5484D), Color(hex: 0x472632))
        default: return (Color(hex: 0x9184D9), Color(hex: 0x353451))
        }
    }
}

/// A faixa de avisos, em cima de tudo na janela.
struct FaixaDeAvisos: View {
    @ObservedObject private var avisos = Avisos.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(avisos.visiveis) { aviso in
                let (cor, fundo) = Avisos.cores(aviso.tipo)
                HStack(spacing: 12) {
                    Circle().fill(cor).frame(width: 9, height: 9)
                    Text(aviso.texto)
                        .font(.system(size: 13))
                        .foregroundStyle(Tema.texto)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let link = aviso.link {
                        Button { avisos.abrir(link) } label: {
                            Text(link.texto).font(.system(size: 12, weight: .medium)).foregroundStyle(cor)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(cor))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if aviso.fechavel {
                        Button { avisos.fechar(aviso) } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.texto.opacity(0.7))
                                .padding(4).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Fechar aviso")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                // Um retângulo, não a cor direto: a cor se espalharia pela barra de título.
                .background(Rectangle().fill(fundo))
                .overlay(alignment: .bottom) { Rectangle().fill(cor).frame(height: 1) }
            }
        }
        .animation(.easeOut(duration: 0.2), value: avisos.visiveis)
    }
}
