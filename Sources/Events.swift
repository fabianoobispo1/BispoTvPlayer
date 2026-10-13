import Foundation
import SwiftUI

/// Os jogos de hoje e dos próximos dias que passam em algum canal da lista,
/// com a mesma lógica da tela de Eventos do TV Box e do celular.
///
/// Duas fontes: a agenda da embedtv diz em que canal cada jogo passa; os
/// placares da ESPN dizem se já começou, o placar e o tempo de jogo, e trazem
/// escudos melhores. Só entra jogo que tem canal (sem canal não há o que
/// assistir), e jogo encerrado sai.
///
/// Bispo TV, por cima do original: a NFL abre a tela num destaque só dela, os
/// outros jogos têm filtro por liga, a agenda vem pelo site quando o
/// embedtv.cc não abre e o tempo de jogo da ESPN sai em português.
struct Jogo: Identifiable, Sendable {
    var casa: String
    var fora: String
    var casaLogo: String
    var foraLogo: String
    var liga: String
    var ligaLogo: String
    var inicio: Date
    var fim: Date
    var canal: Channel
    /// "pre", "in" ou "post", quando a ESPN conhece o jogo.
    var estado = ""
    var placar = ""
    var tempo = ""

    var titulo: String { "\(casa) x \(fora)" }
    var id: String { "\(titulo)|\(inicio.timeIntervalSince1970)" }

    func aoVivo(_ agora: Date) -> Bool {
        estado == "in" || (estado != "post" && agora >= inicio && agora <= fim)
    }
    func acabou(_ agora: Date) -> Bool { estado == "post" || agora > fim }

    var ehNfl: Bool {
        liga.range(of: #"^nfl\b|futebol americano"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum Eventos {
    /// O embedtv.cc não abre em algumas redes de operadora: aí vem pela função do site.
    static let agendas = ["https://embedtv.cc/api/events", "https://bispotv.pages.dev/api/events"]
        .compactMap(URL.init(string:))
    static let ligas = [
        "soccer/bra.1", "soccer/bra.2", "soccer/bra.copa_do_brazil", "soccer/conmebol.libertadores",
        "soccer/conmebol.sudamericana", "soccer/uefa.champions", "soccer/uefa.europa", "soccer/eng.1",
        "soccer/esp.1", "soccer/ita.1", "soccer/ger.1", "soccer/fra.1", "soccer/por.1", "soccer/ned.1",
        "soccer/arg.1", "soccer/ksa.1", "soccer/fifa.world", "soccer/fifa.worldq.conmebol",
        "basketball/nba", "football/nfl", "baseball/mlb", "hockey/nhl", "mma/ufc",
    ]
    static let siglas: Set<String> = ["fc", "ec", "sc", "ac", "afc", "cf", "cd", "club", "clube",
        "esporte", "sport", "futebol", "de", "do", "da", "sp", "rj", "mg", "rs", "pr", "ba", "pe",
        "ce", "go", "sad"]
    static let hora: TimeInterval = 3600

    /// O placar de um jogo na ESPN.
    struct Placar: Sendable {
        var casa, fora, casaLogo, foraLogo, ligaLogo: String
        var inicio: Date
        var estado, golsCasa, golsFora, tempo: String
    }

    private static func baixar(_ url: URL) async -> Data? {
        var pedido = URLRequest(url: url, timeoutInterval: 15)
        pedido.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
              let http = resposta as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return dados
    }

    /// "2026-10-13T21:30:00-03:00" na agenda, "2026-10-16T23:00Z" na ESPN.
    private static func data(_ texto: String?) -> Date? {
        guard let texto, !texto.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: texto) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: texto) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return df.date(from: texto)
    }

    /// O canal pelo fim do endereço do player ("…/premiere-fc" é o Premiere FC).
    static func canalDo(_ url: String, _ canais: [Channel]) -> Channel? {
        let fim = url.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let slug = fim.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        guard !slug.isEmpty else { return nil }
        func chave(_ c: Channel) -> String { c.name.lowercased().replacingOccurrences(of: " ", with: "") }
        return canais.first { chave($0) == slug } ?? canais.first { chave($0).contains(slug) }
    }

    /// A agenda da embedtv: só jogos cujo canal existe na nossa lista.
    private static func lerAgenda(_ dados: Data, _ canais: [Channel]) -> [Jogo] {
        guard let lista = (try? JSONSerialization.jsonObject(with: dados)) as? [[String: Any]] else { return [] }
        var vistos = Set<String>()
        var jogos: [Jogo] = []
        for o in lista {
            // Jogo com dados faltando fica de fora.
            guard let player = (o["players"] as? [String])?.first,
                  let canal = canalDo(player, canais),
                  let times = o["teams"] as? [String: Any],
                  let casa = times["home"] as? [String: Any], let fora = times["away"] as? [String: Any],
                  let nomeCasa = casa["name"] as? String, let nomeFora = fora["name"] as? String,
                  let inicio = data(o["time_start"] as? String) else { continue }
            let liga = o["league"] as? [String: Any]
            let jogo = Jogo(
                casa: nomeCasa, fora: nomeFora,
                casaLogo: (casa["image"] as? String ?? "").emAltaResolucao,
                foraLogo: (fora["image"] as? String ?? "").emAltaResolucao,
                liga: liga?["name"] as? String ?? "",
                ligaLogo: (liga?["image"] as? String ?? "").emAltaResolucao,
                inicio: inicio, fim: data(o["time_end"] as? String) ?? inicio.addingTimeInterval(2 * hora),
                canal: canal)
            guard vistos.insert(jogo.id).inserted else { continue }
            jogos.append(jogo)
        }
        return jogos
    }

    private static func lerEspn(_ dados: Data) -> [Placar] {
        guard let raiz = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any] else { return [] }
        let ligaLogo = (((raiz["leagues"] as? [[String: Any]])?.first?["logos"] as? [[String: Any]])?
            .first?["href"] as? String) ?? ""
        var saida: [Placar] = []
        for ev in raiz["events"] as? [[String: Any]] ?? [] {
            let comps = ((ev["competitions"] as? [[String: Any]])?.first?["competitors"] as? [[String: Any]]) ?? []
            guard let casa = comps.first(where: { $0["homeAway"] as? String == "home" }),
                  let fora = comps.first(where: { $0["homeAway"] as? String != "home" }) else { continue }
            let tipo = (ev["status"] as? [String: Any])?["type"] as? [String: Any]
            let estado = tipo?["state"] as? String ?? ""
            let nfl = ((raiz["leagues"] as? [[String: Any]])?.first?["abbreviation"] as? String) == "NFL"
            let timeCasa = casa["team"] as? [String: Any]
            let timeFora = fora["team"] as? [String: Any]
            saida.append(Placar(
                casa: timeCasa?["name"] as? String ?? "", fora: timeFora?["name"] as? String ?? "",
                casaLogo: timeCasa?["logo"] as? String ?? "", foraLogo: timeFora?["logo"] as? String ?? "",
                ligaLogo: ligaLogo,
                inicio: data(ev["date"] as? String) ?? Date(timeIntervalSince1970: 0),
                estado: estado,
                golsCasa: casa["score"] as? String ?? "", golsFora: fora["score"] as? String ?? "",
                tempo: estado == "in" ? traduzir(tipo?["shortDetail"] as? String ?? "", nfl: nfl) : ""))
        }
        return saida
    }

    /// Bispo TV: "1:59 - 4th" -> "4º quarto · 1:59".
    static func traduzir(_ t: String, nfl: Bool) -> String {
        if t.isEmpty { return "" }
        let periodo = nfl ? "quarto" : "período"
        let casa = { (p: String) in t.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        if casa(#"^(half(time)?|ht)$"#) { return "Intervalo" }
        if casa(#"^(final|ft)"#) { return "Fim" }
        if let r = try? NSRegularExpression(pattern: #"^end of (\d)\w+"#, options: .caseInsensitive),
           let m = r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let n = Range(m.range(at: 1), in: t) { return "Fim do \(t[n])º \(periodo)" }
        if let r = try? NSRegularExpression(pattern: #"^([\d:]+)\s*-\s*(\d)(?:st|nd|rd|th)$"#, options: .caseInsensitive),
           let m = r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let relogio = Range(m.range(at: 1), in: t), let q = Range(m.range(at: 2), in: t) {
            return "\(t[q])º \(periodo) · \(t[relogio])"
        }
        return t.replacingOccurrences(of: "OT", with: "Prorrogação")
    }

    /// Só palavras inteiras de sigla saem: "Palmeiras" e "SE Palmeiras" casam.
    static func chaveTime(_ nome: String) -> String {
        let limpo = nome.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        return limpo.split { !(("a"..."z").contains($0) || ("0"..."9").contains($0)) }
            .map(String.init).filter { !siglas.contains($0) }.joined()
    }

    static func mesmoTime(_ a: String, _ b: String) -> Bool {
        let x = chaveTime(a), y = chaveTime(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || (x.count >= 4 && y.contains(x)) || (y.count >= 4 && x.contains(y))
    }

    /// Nulo quando a agenda não veio.
    static func buscarJogos(_ canais: [Channel]) async -> [Jogo]? {
        async let corpo: Data? = {
            for url in agendas {
                if let dados = await baixar(url) { return dados }
            }
            return nil
        }()
        let espn = await withTaskGroup(of: [Placar].self) { grupo in
            for liga in ligas {
                guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(liga)/scoreboard") else { continue }
                grupo.addTask { await baixar(url).map(lerEspn) ?? [] }
            }
            var todos: [Placar] = []
            for await lidos in grupo { todos += lidos }
            return todos
        }
        guard let dados = await corpo else { return nil }
        return lerAgenda(dados, canais).map { jogo in
            // O mesmo jogo na ESPN: mesmos times (em qualquer ordem) e começo
            // a menos de quatro horas um do outro.
            guard let par = espn.first(where: { e in
                abs(e.inicio.timeIntervalSince(jogo.inicio)) < 4 * hora &&
                    ((mesmoTime(e.casa, jogo.casa) && mesmoTime(e.fora, jogo.fora)) ||
                        (mesmoTime(e.casa, jogo.fora) && mesmoTime(e.fora, jogo.casa)))
            }) else { return jogo }
            // A ESPN pode listar os times na ordem inversa da agenda: aí o
            // escudo e os gols dela vão para o outro lado, senão o time
            // mostrado ganha o escudo do adversário e o placar sai invertido.
            let invertido = !(mesmoTime(par.casa, jogo.casa) && mesmoTime(par.fora, jogo.fora))
            let (logoCasa, logoFora) = invertido ? (par.foraLogo, par.casaLogo) : (par.casaLogo, par.foraLogo)
            let (golsCasa, golsFora) = invertido ? (par.golsFora, par.golsCasa) : (par.golsCasa, par.golsFora)
            var novo = jogo
            if !logoCasa.isEmpty { novo.casaLogo = logoCasa }
            if !logoFora.isEmpty { novo.foraLogo = logoFora }
            if novo.ligaLogo.isEmpty { novo.ligaLogo = par.ligaLogo }
            novo.estado = par.estado
            novo.placar = par.estado == "pre" ? "" : "\(golsCasa) x \(golsFora)"
            novo.tempo = par.tempo
            return novo
        }
    }

    // MARK: - Datas

    private static func diaDe(_ data: Date) -> Date { Calendar.current.startOfDay(for: data) }

    /// Quantos dias do calendário separam a data de hoje.
    static func dias(_ inicio: Date, _ agora: Date) -> Int {
        Calendar.current.dateComponents([.day], from: diaDe(agora), to: diaDe(inicio)).day ?? 0
    }

    private static func formato(_ padrao: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = padrao
        return df
    }

    /// "21:30", "amanhã 16:00" ou "sáb 16:00".
    static func quando(_ inicio: Date, _ agora: Date) -> String {
        let h = formato("HH:mm").string(from: inicio)
        let d = dias(inicio, agora)
        if d <= 0 { return h }
        if d == 1 { return "amanhã \(h)" }
        let semana = formato("EEE").string(from: inicio).replacingOccurrences(of: ".", with: "")
        return "\(semana) \(h)"
    }

    static let grupos = ["Ao vivo agora", "Começa em breve", "Hoje mais tarde", "Amanhã", "Próximos dias"]

    static func grupoDe(_ j: Jogo, _ agora: Date) -> Int {
        if j.aoVivo(agora) { return 0 }
        if j.inicio.timeIntervalSince(agora) <= 2 * hora { return 1 }
        let d = dias(j.inicio, agora)
        if d <= 0 { return 2 }
        return d == 1 ? 3 : 4
    }
}

@MainActor
final class EventsService: ObservableObject {
    static let shared = EventsService()

    /// Nulo enquanto a primeira busca não voltou.
    @Published private(set) var jogos: [Jogo]?
    @Published private(set) var erro = false
    @Published private(set) var agora = Date()
    private var buscando = false

    private init() {}

    func carregar(_ canais: [Channel]) async {
        guard !buscando, !canais.isEmpty else { return }
        buscando = true
        defer { buscando = false }
        let lidos = await Eventos.buscarJogos(canais)
        agora = Date()
        if let lidos {
            jogos = lidos
            erro = false
        } else {
            erro = true
        }
    }
}

struct EventsView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var service = EventsService.shared

    /// O placar anda: com a tela aberta, busca de novo a cada minuto.
    private static let intervalo: Duration = .seconds(60)
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 18)]
    @State private var liga = "Todas"

    /// Canal adulto não entra na agenda.
    private var canais: [Channel] {
        model.channels.filter { Categoria.de($0) != .adulto }
    }

    private var restantes: [Jogo] {
        (service.jogos ?? []).filter { !$0.acabou(service.agora) }.sorted { $0.inicio < $1.inicio }
    }

    /// Os jogos fora da NFL, na liga escolhida, separados pelos `Eventos.grupos`.
    private func grupos(_ lista: [Jogo]) -> [(titulo: String, jogos: [Jogo])] {
        let agora = service.agora
        var listas = Array(repeating: [Jogo](), count: Eventos.grupos.count)
        for j in lista { listas[Eventos.grupoDe(j, agora)].append(j) }
        return zip(Eventos.grupos, listas).filter { !$0.1.isEmpty }.map { (titulo: $0.0, jogos: $0.1) }
    }

    var body: some View {
        let restantes = self.restantes
        Group {
            if service.jogos == nil && !service.erro {
                VStack {
                    Spacer()
                    ProgressView("Carregando eventos...")
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if service.jogos != nil {
                            Text(resumo(restantes))
                                .font(.system(size: 12))
                                .foregroundStyle(Tema.neutro500)
                        }
                        if restantes.isEmpty {
                            vazio
                        } else {
                            conteudo(restantes)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // Enquanto a tela está aberta; sai dela, a busca para.
        .task(id: model.channels.isEmpty) {
            while !Task.isCancelled {
                await service.carregar(canais)
                try? await Task.sleep(for: Self.intervalo)
            }
        }
    }

    /// Bispo TV: a NFL num destaque só dela, ao vivo primeiro; depois os
    /// outros jogos pelos grupos do original, com o filtro por liga.
    @ViewBuilder
    private func conteudo(_ restantes: [Jogo]) -> some View {
        let agora = service.agora
        let nfl = restantes.filter(\.ehNfl).sorted { ($0.aoVivo(agora) ? 0 : 1, $0.inicio) < ($1.aoVivo(agora) ? 0 : 1, $1.inicio) }
        let outros = restantes.filter { !$0.ehNfl }
        let contagem = Dictionary(grouping: outros, by: \.liga).filter { !$0.key.isEmpty }
        let ligas = contagem.keys.sorted { (contagem[$0]!.count, $1) > (contagem[$1]!.count, $0) }
        let filtrados = liga == "Todas" ? outros : outros.filter { $0.liga == liga }

        if !nfl.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "football.fill").foregroundStyle(Tema.acento)
                    Text("NFL").font(.system(size: 17, weight: .medium)).foregroundStyle(Tema.texto)
                    Text("\(nfl.count) \(nfl.count == 1 ? "jogo" : "jogos")")
                        .font(.caption).foregroundStyle(Tema.neutro500)
                }
                grade(nfl)
            }
            .padding(14)
            .background(LinearGradient(colors: [Tema.secao.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tema.acento.opacity(0.25)))
        }
        if !outros.isEmpty {
            if !nfl.isEmpty {
                Text("Outros jogos").font(.system(size: 17, weight: .medium)).foregroundStyle(Tema.texto)
            }
            if ligas.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["Todas"] + ligas, id: \.self) { nome in
                            Button { liga = nome } label: {
                                Text(nome)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(liga == nome ? Tema.acento.opacity(0.14) : Color.white.opacity(0.06)))
                                    .overlay(Capsule().strokeBorder(liga == nome ? Tema.acento : .clear, lineWidth: 1))
                                    .foregroundStyle(liga == nome ? Tema.acento : Tema.texto)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ForEach(grupos(filtrados), id: \.titulo) { grupo in
                HStack(spacing: 7) {
                    if grupo.titulo == Eventos.grupos[0] {
                        Circle().fill(Tema.acento300).frame(width: 8, height: 8)
                    }
                    Text(grupo.titulo)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tema.texto)
                }
                .padding(.top, 4)
                grade(grupo.jogos)
            }
        }
    }

    private func grade(_ lista: [Jogo]) -> some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(lista) { jogo in
                CartaoJogo(jogo: jogo, agora: service.agora) {
                    model.abrirCanalDoJogo(jogo.canal)
                }
            }
        }
    }

    private func resumo(_ restantes: [Jogo]) -> String {
        let total = restantes.count
        let vivos = restantes.filter { $0.aoVivo(service.agora) }.count
        return "\(total) \(total == 1 ? "jogo" : "jogos") nos canais da lista · \(vivos) ao vivo"
    }

    private var vazio: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 44))
                .foregroundStyle(Tema.neutro500)
            Text(service.erro
                 ? "Não deu para carregar a agenda agora. Tentando de novo em um minuto."
                 : "Nenhum jogo nos canais da lista agora. A agenda se atualiza sozinha.")
                .font(.system(size: 13))
                .foregroundStyle(Tema.neutro500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// Escudo, logo de liga: pelo mesmo carregador dos logos dos canais, que
/// guarda em disco e não pisca a cada atualização da agenda.
private struct LogoRemoto<Reserva: View>: View {
    let endereco: String
    let tamanho: CGFloat
    @ViewBuilder let reserva: () -> Reserva
    @ObservedObject private var logos = LogoLoader.shared

    var body: some View {
        if let url = URL(string: endereco), !endereco.isEmpty, let imagem = logos.image(for: url) {
            Image(nsImage: imagem)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: tamanho, height: tamanho)
        } else {
            reserva().frame(width: tamanho, height: tamanho)
        }
    }
}

struct CartaoJogo: View {
    let jogo: Jogo
    let agora: Date
    let action: () -> Void

    var body: some View {
        let vivo = jogo.aoVivo(agora)
        Button(action: action) {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    LogoRemoto(endereco: jogo.ligaLogo, tamanho: 18) {
                        Image(systemName: "trophy")
                            .font(.system(size: 12))
                            .foregroundStyle(Tema.neutro500)
                    }
                    Text(jogo.liga)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.neutro400)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    selo(vivo)
                }

                HStack(alignment: .top, spacing: 8) {
                    time(jogo.casa, jogo.casaLogo)
                    Group {
                        if jogo.placar.isEmpty {
                            Text("X")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(Tema.neutro500)
                        } else {
                            Text(jogo.placar)
                                .font(.system(size: 24, weight: .black))
                                .foregroundStyle(Tema.texto)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(minWidth: 70)
                    .frame(height: 52)
                    time(jogo.fora, jogo.foraLogo)
                }

                HStack(spacing: 8) {
                    ChannelIcon(channel: jogo.canal, size: 24)
                    Text(jogo.canal.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.texto)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Assistir").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Tema.acento)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(Tema.acento, lineWidth: 1))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(vivo ? Tema.acento900 : Tema.superficie))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(vivo ? Tema.acento.opacity(0.6) : Tema.neutro800, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(jogo.titulo), no canal \(jogo.canal.name)")
    }

    @ViewBuilder
    private func selo(_ vivo: Bool) -> some View {
        if vivo {
            HStack(spacing: 5) {
                Circle().fill(Tema.acento300).frame(width: 7, height: 7)
                Text(["AO VIVO", jogo.tempo].filter { !$0.isEmpty }.joined(separator: "  "))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tema.acento300)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Tema.acento.opacity(0.18)))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 10))
                Text(Eventos.quando(jogo.inicio, agora))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Tema.neutro300)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Tema.neutro900))
        }
    }

    private func time(_ nome: String, _ logo: String) -> some View {
        VStack(spacing: 6) {
            LogoRemoto(endereco: logo, tamanho: 52) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Text(nome.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Tema.neutro300))
            }
            Text(nome)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Tema.texto)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

extension String {
    /// Escudos da agenda vêm do CDN do 365scores pedidos em 34 px (`w_34,h_34`)
    /// e em qualidade econômica: borrados. O CDN monta a imagem pelo endereço,
    /// então pedir 256 px e qualidade máxima traz o original (350 a 415 px);
    /// `c_limit` nunca amplia além dele.
    var emAltaResolucao: String {
        let marca = "imagecache.365scores.com/image/upload/"
        guard let faixa = range(of: marca) else { return self }
        let resto = self[faixa.upperBound...]
        let fim = resto.firstIndex(of: "/") ?? endIndex
        let ajustes = self[faixa.upperBound..<fim].split(separator: ",").map { p -> String in
            if p.hasPrefix("w_") { return "w_256" }
            if p.hasPrefix("h_") { return "h_256" }
            if p == "q_auto:eco" { return "q_auto:best" }
            return String(p)
        }
        return String(self[..<faixa.upperBound]) + ajustes.joined(separator: ",") + String(self[fim...])
    }
}
