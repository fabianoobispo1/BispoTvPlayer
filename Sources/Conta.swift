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
    }

    struct Erro: LocalizedError {
        let mensagem: String
        let status: Int
        var errorDescription: String? { mensagem }
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

    // MARK: - Ações

    func entrar(email: String, senha: String) async throws {
        try await abrirSessao("/entrar", ["email": email, "senha": senha])
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

    /// Confere a sessão por trás, na abertura. Só um 401 tira a pessoa.
    func conferir() async {
        guard token != nil else { return }
        do {
            let resposta = try await pedir("/eu")
            if let conta = resposta["conta"], let i = Self.info(de: conta) { gravar(token: token, info: i) }
        } catch let erro as Erro where erro.status == 401 {
            gravar(token: nil, info: nil)
        } catch {
            // Sem rede: segue com a sessão guardada.
        }
    }

    // MARK: - Servidor

    private func abrirSessao(_ caminho: String, _ campos: [String: String]) async throws {
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
            throw Erro(mensagem: json["erro"] as? String ?? "Não deu certo. Tente de novo.", status: status)
        }
        return json
    }

    private static func info(de valor: Any) -> Info? {
        guard let d = valor as? [String: Any], let id = d["id"] as? Int, let email = d["email"] as? String else { return nil }
        return Info(id: id, email: email, nome: d["nome"] as? String, trocarSenha: d["trocarSenha"] as? Bool ?? false)
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
    private static let servico = Conta.deTeste ? "dev.bispotv.player.sessao.teste" : "dev.bispotv.player.sessao"

    private static var consulta: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servico,
         kSecAttrAccount as String: "token"]
    }

    static func ler() -> String? {
        var q = consulta
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &resultado) == errSecSuccess, let dados = resultado as? Data else { return nil }
        return String(data: dados, encoding: .utf8)
    }

    static func gravar(_ token: String) {
        apagar()
        var q = consulta
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func apagar() {
        SecItemDelete(consulta as CFDictionary)
    }
}
