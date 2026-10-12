import AppKit
import Foundation
import Security

/// A conta de quem usa o app.
///
/// O login é obrigatório (conta nova pelo WhatsApp, entrar por e-mail e senha) e é a mesma
/// conta do site, da TV Box e do Windows: o servidor é o BispoTvApi. O token
/// da sessão fica no Chaveiro do macOS; sem rede, quem já entrou continua
/// usando, e um token recusado pelo servidor (conta bloqueada, senha trocada
/// noutro lugar) leva de volta à tela de entrar.
@MainActor
final class Conta: ObservableObject {
    static let shared = Conta()

    struct Info: Codable, Equatable {
        let id: Int
        let email: String
        let nome: String?
        var trocarSenha: Bool
        /// A conta tem um WhatsApp ligado (dá para resetar a senha pelo robô).
        var whatsapp: Bool? = nil
        var plano: String? = nil
        var pagoAte: String? = nil
        var situacao: String? = nil
    }

    struct Erro: LocalizedError {
        let mensagem: String
        let status: Int
        /// 409: a conta já está no limite; a pessoa escolhe um destes para sair.
        var aparelhos: [Aparelho] = []
        var situacao: String? = nil
        var errorDescription: String? { mensagem }
    }

    /// Um aparelho conectado à conta (a lista vem quando ela está cheia).
    struct Aparelho: Identifiable, Equatable {
        let id: Int
        let nome: String
        let plataforma: String
        let usadoEm: Date?
    }

    /// O BispoTvApi. BISPOTV_API (ex.: http://localhost:8791/v1) aponta para
    /// outro, para conferir telas: aí a sessão fica à parte da de verdade.
    nonisolated static let api: URL = {
        if let outro = ProcessInfo.processInfo.environment["BISPOTV_API"], let url = URL(string: outro) { return url }
        return URL(string: "https://bispotv-api.fabianoobispo.com.br/v1")!
    }()
    nonisolated static let deTeste = ProcessInfo.processInfo.environment["BISPOTV_API"] != nil

    private let base = Conta.api.appendingPathComponent("conta")
    private let chaveInfo = Conta.deTeste ? "conta.info.teste" : "conta.info"

    @Published private(set) var info: Info?
    private var token: String?

    private init() {
        token = Chaveiro.ler()
        if token != nil, let dados = UserDefaults.standard.data(forKey: chaveInfo) {
            info = try? JSONDecoder().decode(Info.self, from: dados)
        }
        if info == nil { token = nil }
    }

    var logado: Bool { info != nil }

    /// O token da sessão, para a sincronização falar com o servidor.
    var tokenAtual: String? { token }

    func atualizarSituacao(_ situacao: String) {
        guard var info, info.situacao != situacao else { return }
        info.situacao = situacao
        gravar(token: token, info: info)
        if situacao == "bloqueada" { PlayerModel.shared.pararTudo() }
    }

    // MARK: - Ações

    /// `desconectar`: o aparelho escolhido para sair quando a conta está cheia.
    func entrar(email: String, senha: String, desconectar: Int? = nil) async throws {
        var campos: [String: Any] = ["email": email, "senha": senha]
        if let desconectar { campos["desconectar"] = desconectar }
        try await abrirSessao("/entrar", campos)
    }

    func trocarSenha(atual: String, nova: String) async throws {
        _ = try await pedir("/senha", corpo: ["atual": atual, "nova": nova])
        if var i = info {
            i.trocarSenha = false
            gravar(token: token, info: i)
        }
    }

    func sair() async {
        _ = try? await pedir("/sair", corpo: [:])
        gravar(token: nil, info: nil)
    }

    /// Ligar o WhatsApp à conta: gera o código e abre a conversa com
    /// "VINCULAR <código>"; o robô liga o número de quem mandar.
    func ligarWhatsapp() async throws {
        let resposta = try await pedir("/whatsapp", corpo: [:])
        guard let link = resposta["link"] as? String, let url = URL(string: link) else {
            throw Erro(mensagem: "Resposta inesperada do servidor.", status: 0)
        }
        NSWorkspace.shared.open(url)
        // Volta conferindo por um tempo, para o menu e o aviso saberem que ligou.
        for _ in 0..<40 where info?.whatsapp != true {
            try? await Task.sleep(for: .seconds(6))
            await conferir()
        }
    }

    /// Confere a sessão por trás, na abertura. Só um 401 tira a pessoa.
    func conferir() async {
        guard token != nil else { return }
        do {
            let resposta = try await pedir("/eu")
            if let conta = resposta["conta"], let i = Self.info(de: conta) { gravar(token: token, info: i) }
        } catch let erro as Erro where erro.status == 403 && erro.situacao == "bloqueada" {
            atualizarSituacao("bloqueada")
        } catch let erro as Erro where erro.status == 401 {
            gravar(token: nil, info: nil)
        } catch {
            // Sem rede: segue com a sessão guardada.
        }
    }

    // MARK: - Servidor

    private func abrirSessao(_ caminho: String, _ campos: [String: Any]) async throws {
        var corpo: [String: Any] = campos
        corpo["deviceId"] = Telemetria.shared.idDoAparelho
        corpo["platform"] = "mac"
        let resposta = try await pedir(caminho, corpo: corpo)
        guard let novo = resposta["token"] as? String, let conta = resposta["conta"], let i = Self.info(de: conta) else {
            throw Erro(mensagem: "Resposta inesperada do servidor.", status: 0)
        }
        gravar(token: novo, info: i)
    }

    private func pedir(_ caminho: String, corpo: [String: Any]? = nil) async throws -> [String: Any] {
        var pedido = URLRequest(url: base.appendingPathComponent(String(caminho.dropFirst())))
        pedido.timeoutInterval = 20
        if let corpo {
            pedido.httpMethod = "POST"
            pedido.setValue("application/json", forHTTPHeaderField: "content-type")
            pedido.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        }
        if let token { pedido.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }

        let dados: Data
        let resposta: URLResponse
        do {
            (dados, resposta) = try await URLSession.shared.data(for: pedido)
        } catch {
            throw Erro(mensagem: "Sem conexão com o servidor. Tente de novo.", status: 0)
        }
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] ?? [:]
        guard (200...299).contains(status) else {
            throw Erro(mensagem: json["erro"] as? String ?? "Não deu certo. Tente de novo.", status: status,
                       aparelhos: status == 409 ? Self.aparelhos(de: json["aparelhos"]) : [],
                       situacao: json["situacao"] as? String)
        }
        return json
    }

    private static func aparelhos(de valor: Any?) -> [Aparelho] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (valor as? [[String: Any]] ?? []).compactMap { a in
            guard let id = a["id"] as? Int else { return nil }
            return Aparelho(id: id, nome: a["nome"] as? String ?? "Aparelho", plataforma: a["plataforma"] as? String ?? "",
                            usadoEm: (a["usadoEm"] as? String).flatMap(iso.date(from:)))
        }
    }

    private static func info(de valor: Any) -> Info? {
        guard let d = valor as? [String: Any], let id = d["id"] as? Int, let email = d["email"] as? String else { return nil }
        return Info(id: id, email: email, nome: d["nome"] as? String, trocarSenha: d["trocarSenha"] as? Bool ?? false,
                    whatsapp: d["whatsapp"] as? Bool, plano: d["plano"] as? String, pagoAte: d["pagoAte"] as? String,
                    situacao: d["situacao"] as? String)
    }

    private func gravar(token novo: String?, info nova: Info?) {
        let entrou = info == nil && nova != nil
        let saiu = info != nil && nova == nil
        token = novo
        info = nova
        if let novo { Chaveiro.gravar(novo) } else { Chaveiro.apagar() }
        if let nova, let dados = try? JSONEncoder().encode(nova) {
            UserDefaults.standard.set(dados, forKey: chaveInfo)
        } else {
            UserDefaults.standard.removeObject(forKey: chaveInfo)
        }
        // O player só toca com alguém logado; favoritos e progresso são da conta.
        if entrou {
            PlayerModel.shared.abrirUltimoCanal()
            Task { await Sincronia.shared.sincronizar() }
        }
        if saiu {
            PlayerModel.shared.pararTudo()
            Sincronia.shared.esquecer()
        }
    }
}

/// O token da sessão no Chaveiro (item genérico deste app).
private enum Chaveiro {
    private static let servico = "dev.bispotv.player.sessao"

    private static var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servico,
         kSecAttrAccount as String: "token"]
    }

    /// No modo de teste (BISPOTV_API) a sessão fica nas preferências: o
    /// Chaveiro pediria a senha do Mac a cada build nova.
    private static let chaveTeste = "sessao.teste"

    static func ler() -> String? {
        if Conta.deTeste { return UserDefaults.standard.string(forKey: chaveTeste) }
        var q = consulta
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultado) == errSecSuccess, let dados = resultado as? Data else { return nil }
        return String(data: dados, encoding: .utf8)
    }

    static func gravar(_ token: String) {
        if Conta.deTeste { UserDefaults.standard.set(token, forKey: chaveTeste); return }
        apagar()
        var q = consulta
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func apagar() {
        if Conta.deTeste { UserDefaults.standard.removeObject(forKey: chaveTeste); return }
        SecItemDelete(consulta as CFDictionary)
    }
}
