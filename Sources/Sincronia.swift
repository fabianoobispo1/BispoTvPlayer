import Foundation

/// Favoritos e "continuar assistindo" da conta, iguais em todos os aparelhos.
///
/// O servidor (POST /v1/sync no BispoTvApi) guarda, por conta, cada favorito e
/// onde cada filme ou episódio parou, com a hora da última mudança: vale a mais
/// nova. Este Mac manda o que mudou aqui e recebe o que mudou nos outros desde
/// o último cursor. Na primeira vez de uma conta, o que já estava marcado aqui
/// sobe junto; ao sair dela, sai deste Mac.
///
/// Chaves combinadas com o site, o Windows e a TV Box:
///   fav  c|<nome do canal>
///   fav  v|<título do acervo>      { serie, letra, ano, reservado }
///   prog f|<título> ou s|<série>|<temporada>|<episódio>   { pos, dur }
@MainActor
final class Sincronia {
    static let shared = Sincronia()

    private let endereco = Conta.api.appendingPathComponent("sync")
    private let chaveEstado = "sincronia.estado"

    private struct Pendente: Codable {
        let tipo: String
        let chave: String
        /// O valor em JSON; nil é "desmarcado/apagado".
        let valor: String?
        let alteradoEm: Int64
    }

    private struct Estado: Codable {
        var conta: Int?
        var cursor: Int64 = 0
        /// "tipo|chave" -> hora da última mudança conhecida (daqui ou de fora).
        var marcas: [String: Int64] = [:]
        var pendentes: [Pendente] = []
    }

    private var estado: Estado
    private var voo: Task<Void, Never>?
    private var agendada: Task<Void, Never>?
    private var quando = Date.distantFuture

    private init() {
        if let dados = UserDefaults.standard.data(forKey: chaveEstado),
           let e = try? JSONDecoder().decode(Estado.self, from: dados) {
            estado = e
        } else {
            estado = Estado()
        }
        // Na abertura e depois de cinco em cinco minutos.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while let self {
                await self.sincronizar()
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            }
        }
    }

    private static var agoraMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func gravar() {
        if let dados = try? JSONEncoder().encode(estado) {
            UserDefaults.standard.set(dados, forKey: chaveEstado)
        }
    }

    // MARK: - O que muda aqui

    private func mudar(_ tipo: String, _ chave: String, _ valor: [String: Any]?, espera: Double = 3) {
        guard Conta.shared.logado else { return }
        let agora = Self.agoraMs
        let texto = valor.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) }
        estado.marcas["\(tipo)|\(chave)"] = agora
        estado.pendentes.removeAll { $0.tipo == tipo && $0.chave == chave }
        estado.pendentes.append(Pendente(tipo: tipo, chave: chave, valor: texto, alteradoEm: agora))
        gravar()
        agendar(espera)
    }

    func favoritoCanal(_ nome: String, marcado: Bool) {
        mudar("fav", "c|\(nome)", marcado ? [:] : nil)
    }

    func favoritoVod(_ item: VodFavoritos.Item, marcado: Bool) {
        mudar("fav", "v|\(item.titulo)", marcado
              ? ["serie": item.serie, "letra": item.letra, "ano": item.ano, "reservado": item.reservado]
              : nil)
    }

    /// O player grava a cada poucos segundos: a fila guarda só a última
    /// posição de cada título e o envio sai em até 30 s.
    func progresso(_ chave: String, posicao: Double?, duracao: Double?) {
        if let posicao, let duracao {
            mudar("prog", chave, ["pos": Int(posicao), "dur": Int(duracao)], espera: 30)
        } else {
            mudar("prog", chave, nil)
        }
    }

    // MARK: - Conversa com o servidor

    private func agendar(_ segundos: Double) {
        let alvo = Date().addingTimeInterval(segundos)
        if agendada != nil, quando <= alvo { return }
        agendada?.cancel()
        quando = alvo
        agendada = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.agendada = nil
            self.quando = .distantFuture
            await self.sincronizar()
        }
    }

    /// Manda a fila e recebe o que mudou. Com uma em andamento, espera por
    /// ela e, sobrando algo na fila, manda de novo.
    func sincronizar() async {
        // Conferindo telas com outra API (BISPOTV_API): nada de misturar os
        // favoritos deste Mac com os da conta de teste.
        guard !Conta.deTeste else { return }
        if let voo {
            await voo.value
            if estado.pendentes.isEmpty { return }
        }
        let tarefa = Task { await self.rodar() }
        voo = tarefa
        await tarefa.value
        voo = nil
    }

    private func rodar() async {
        guard let token = Conta.shared.tokenAtual, let conta = Conta.shared.info else { return }
        if let dona = estado.conta, dona != conta.id {
            estado = Estado()
        }
        if estado.conta == nil {
            // Primeira vez desta conta neste Mac: o que já estava marcado sobe.
            estado.conta = conta.id
            subirOQueJaExiste()
        }

        let enviados = Array(estado.pendentes.prefix(2000))
        let itens: [[String: Any]] = enviados.map { p in
            var d: [String: Any] = ["tipo": p.tipo, "chave": p.chave, "alteradoEm": p.alteradoEm]
            if let v = p.valor, let dados = v.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: dados) {
                d["valor"] = obj
            } else {
                d["valor"] = NSNull()
            }
            return d
        }
        var pedido = URLRequest(url: endereco)
        pedido.httpMethod = "POST"
        pedido.timeoutInterval = 30
        pedido.setValue("application/json", forHTTPHeaderField: "content-type")
        pedido.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        pedido.httpBody = try? JSONSerialization.data(withJSONObject: ["desde": estado.cursor, "itens": itens])

        defer { agendar(estado.pendentes.isEmpty ? 300 : 15) }
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              (resposta as? HTTPURLResponse)?.statusCode == 200,
              let corpo = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
        else { return } // sem rede: a fila espera a próxima vez

        let mandados = Set(enviados.map { "\($0.tipo)|\($0.chave)|\($0.alteradoEm)" })
        estado.pendentes.removeAll { mandados.contains("\($0.tipo)|\($0.chave)|\($0.alteradoEm)") }
        for item in corpo["itens"] as? [[String: Any]] ?? [] {
            aplicar(item)
        }
        if let cursor = (corpo["cursor"] as? NSNumber)?.int64Value { estado.cursor = cursor }
        gravar()
    }

    /// O que veio do servidor, se for mais novo que o que este Mac sabe.
    private func aplicar(_ item: [String: Any]) {
        guard let tipo = item["tipo"] as? String, let chave = item["chave"] as? String,
              let alterado = (item["alteradoEm"] as? NSNumber)?.int64Value else { return }
        let marca = "\(tipo)|\(chave)"
        if let conhecida = estado.marcas[marca], conhecida >= alterado { return }
        estado.marcas[marca] = alterado
        let valor = item["valor"] as? [String: Any]

        if tipo == "fav", chave.hasPrefix("c|") {
            let nome = String(chave.dropFirst(2))
            if let canal = PlayerModel.shared.channels.first(where: { $0.name == nome }) {
                PlayerModel.shared.definirFavorito(canal, marcado: valor != nil)
            }
        } else if tipo == "fav", chave.hasPrefix("v|") {
            let titulo = String(chave.dropFirst(2))
            let serie = valor?["serie"] as? Bool ?? false
            let ano = valor?["ano"] as? String ?? ""
            let letra = (valor?["letra"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Self.letra(de: titulo)
            let reservado = valor?["reservado"] as? Bool ?? false
            VodFavoritos.shared.definir(.init(titulo: titulo, serie: serie, letra: letra, reservado: reservado, ano: ano),
                                        marcado: valor != nil)
        } else if tipo == "prog" {
            if let valor, let pos = (valor["pos"] as? NSNumber)?.doubleValue, let dur = (valor["dur"] as? NSNumber)?.doubleValue, dur > 0 {
                Progresso.aplicar(chave, posicao: pos, duracao: dur, quando: Double(alterado) / 1000)
            } else {
                Progresso.apagar(chave)
            }
        }
    }

    private func subirOQueJaExiste() {
        let agora = Self.agoraMs
        func fila(_ tipo: String, _ chave: String, _ valor: [String: Any]) {
            guard let dados = try? JSONSerialization.data(withJSONObject: valor) else { return }
            estado.marcas["\(tipo)|\(chave)"] = agora
            estado.pendentes.append(Pendente(tipo: tipo, chave: chave, valor: String(data: dados, encoding: .utf8), alteradoEm: agora))
        }
        for nome in PlayerModel.shared.nomesFavoritos { fila("fav", "c|\(nome)", [:]) }
        for item in VodFavoritos.shared.itens {
            fila("fav", "v|\(item.titulo)", ["serie": item.serie, "letra": item.letra, "ano": item.ano, "reservado": item.reservado])
        }
        for andamento in Progresso.emAndamento() {
            let pos = Progresso.posicao(andamento.chave), dur = Progresso.duracao(andamento.chave)
            if pos > 0, dur > 0 { fila("prog", andamento.chave, ["pos": Int(pos), "dur": Int(dur)]) }
        }
        gravar()
    }

    /// Ao sair da conta: favoritos e progresso eram dela, não deste Mac.
    func esquecer() {
        guard !Conta.deTeste else { return }
        agendada?.cancel()
        agendada = nil
        estado = Estado()
        gravar()
        PlayerModel.shared.esquecerFavoritos()
        VodFavoritos.shared.esvaziar()
        Progresso.apagarTudo()
    }

    /// A letra do acervo onde o título mora, para quando quem marcou não disse.
    static func letra(de titulo: String) -> String {
        let primeira = titulo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return primeira.range(of: "^[A-Z]$", options: .regularExpression) != nil ? primeira : "#"
    }
}
