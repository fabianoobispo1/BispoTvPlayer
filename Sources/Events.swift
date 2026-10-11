import Foundation

struct EventTeam: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let image: String
}

struct EventTeams: Decodable {
    let home: EventTeam?
    let away: EventTeam?
}

struct EventLeague: Decodable {
    let name: String
    let image: String?
}

struct Event: Decodable, Identifiable {
    let id: Int
    let slug: String
    let title: String
    let league: EventLeague?
    let teams: EventTeams?
    let time_start: String
    let time_end: String
    let players: [String]

    var channelSlug: String? {
        guard let firstPlayer = players.first, let url = URL(string: firstPlayer) else { return nil }
        return url.lastPathComponent
    }

    // Bispo TV: o estado de verdade, vindo da ESPN (ver Placares, abaixo).
    var inicio: Date = .distantPast
    var fim: Date = .distantPast
    /// "pre", "in" ou "post", quando a ESPN conhece o jogo.
    var estado = ""
    /// "14 x 16" (casa x fora), quando já começou.
    var placar = ""
    /// "4º quarto · 1:59", "45'", "Intervalo"...
    var tempo = ""

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, league, teams, time_start, time_end, players
    }

    var ehNfl: Bool {
        (league?.name ?? "").range(of: #"^nfl\b|futebol americano"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func aoVivo(_ agora: Date = Date()) -> Bool {
        estado == "in" || (estado != "post" && agora >= inicio && agora <= fim)
    }

    func acabou(_ agora: Date = Date()) -> Bool {
        estado == "post" || (estado != "in" && agora > fim)
    }

    var formattedTime: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateFormat = Calendar.current.isDateInToday(inicio) ? "HH:mm" : "EEE HH:mm"
        return df.string(from: inicio)
    }
}

/// Os placares públicos da ESPN, como na TV Box, no site e no celular: as
/// mesmas ligas e a mesma regra para casar os nomes dos times. Mudou lá, muda aqui.
enum Placares {
    struct Placar {
        let casa: String, fora: String, inicio: Date, estado: String, placar: String, tempo: String
    }

    static let ligas = [
        "soccer/bra.1", "soccer/bra.2", "soccer/bra.copa_do_brazil", "soccer/conmebol.libertadores",
        "soccer/conmebol.sudamericana", "soccer/uefa.champions", "soccer/uefa.europa", "soccer/eng.1",
        "soccer/esp.1", "soccer/ita.1", "soccer/ger.1", "soccer/fra.1", "soccer/por.1", "soccer/ned.1",
        "soccer/arg.1", "soccer/ksa.1", "soccer/fifa.world", "soccer/fifa.worldq.conmebol",
        "basketball/nba", "football/nfl", "baseball/mlb", "hockey/nhl", "mma/ufc",
    ]

    private static let siglas: Set<String> = ["fc", "ec", "sc", "ac", "afc", "cf", "cd", "club", "clube", "esporte",
        "sport", "futebol", "de", "do", "da", "sp", "rj", "mg", "rs", "pr", "ba", "pe", "ce", "go", "sad"]

    static func buscar() async -> [Placar] {
        await withTaskGroup(of: [Placar].self) { grupo in
            for liga in ligas {
                grupo.addTask {
                    guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(liga)/scoreboard"),
                          let (dados, _) = try? await URLSession.shared.data(from: url),
                          let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
                    else { return [] }
                    return ler(json, nfl: liga == "football/nfl")
                }
            }
            var todos: [Placar] = []
            for await lista in grupo { todos += lista }
            return todos
        }
    }

    private static func ler(_ json: [String: Any], nfl: Bool) -> [Placar] {
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return (json["events"] as? [[String: Any]] ?? []).compactMap { ev in
            guard let comps = ((ev["competitions"] as? [[String: Any]])?.first)?["competitors"] as? [[String: Any]],
                  let casa = comps.first(where: { $0["homeAway"] as? String == "home" }),
                  let fora = comps.first(where: { $0["homeAway"] as? String != "home" }),
                  let tipo = (ev["status"] as? [String: Any])?["type"] as? [String: Any],
                  let estado = tipo["state"] as? String, ["pre", "in", "post"].contains(estado)
            else { return nil }
            let nome = { (c: [String: Any]) in ((c["team"] as? [String: Any])?["name"] as? String) ?? "" }
            let gols = { (c: [String: Any]) in (c["score"] as? String) ?? "0" }
            let data = (ev["date"] as? String).flatMap { utc.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? .distantPast
            return Placar(casa: nome(casa), fora: nome(fora), inicio: data, estado: estado,
                          placar: estado == "pre" ? "" : "\(gols(casa)) x \(gols(fora))",
                          tempo: estado == "in" ? traduzir(tipo["shortDetail"] as? String ?? "", nfl: nfl) : "")
        }
    }

    /// "1:59 - 4th" -> "4º quarto · 1:59".
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

    private static func chave(_ nome: String) -> String {
        nome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "pt_BR"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !siglas.contains($0) }
            .joined()
    }

    /// "Palmeiras" e "SE Palmeiras", "Atlético-MG" e "Atletico Mineiro".
    static func mesmoTime(_ a: String, _ b: String) -> Bool {
        let x = chave(a), y = chave(b)
        if x.isEmpty || y.isEmpty { return false }
        return x == y || (x.count >= 4 && y.contains(x)) || (y.count >= 4 && x.contains(y))
    }
}

@MainActor
final class EventsService: ObservableObject {
    static let shared = EventsService()

    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var error: String?

    /// A agenda com o placar da ESPN junto; jogo encerrado sai. Com `forcar`,
    /// busca de novo mesmo já tendo a lista (o placar anda).
    func loadEvents(forcar: Bool = false) async {
        guard events.isEmpty || forcar else { return }
        if events.isEmpty { isLoading = true }
        error = nil
        defer { isLoading = false }

        do {
            async let placares = Placares.buscar()
            let agenda = try await baixarAgenda()
            let espn = await placares
            let iso = ISO8601DateFormatter()
            let agora = Date()
            var vistos = Set<String>()
            var lista: [Event] = []
            for var ev in agenda {
                guard let inicio = iso.date(from: ev.time_start) else { continue }
                guard vistos.insert("\(ev.title)|\(inicio.timeIntervalSince1970)").inserted else { continue }
                ev.inicio = inicio
                ev.fim = iso.date(from: ev.time_end) ?? inicio.addingTimeInterval(2 * 3600)
                let casa = ev.teams?.home?.name ?? "", fora = ev.teams?.away?.name ?? ""
                if let par = espn.first(where: { p in
                    abs(p.inicio.timeIntervalSince(inicio)) < 4 * 3600 &&
                        ((Placares.mesmoTime(p.casa, casa) && Placares.mesmoTime(p.fora, fora)) ||
                         (Placares.mesmoTime(p.casa, fora) && Placares.mesmoTime(p.fora, casa)))
                }) {
                    ev.estado = par.estado
                    ev.tempo = par.tempo
                    // Casa e fora podem vir trocados: o placar segue a agenda.
                    ev.placar = Placares.mesmoTime(par.casa, fora) && !par.placar.isEmpty
                        ? par.placar.components(separatedBy: " x ").reversed().joined(separator: " x ")
                        : par.placar
                }
                if !ev.acabou(agora) { lista.append(ev) }
            }
            events = lista.sorted { a, b in
                a.aoVivo(agora) != b.aoVivo(agora) ? a.aoVivo(agora) : a.inicio < b.inicio
            }
        } catch {
            // O motivo técnico vai para o log; na tela, só o que a pessoa
            // precisa saber.
            Log.shared.write("eventos: \(error.localizedDescription)")
            if events.isEmpty { self.error = "Eventos indisponíveis no momento." }
        }
    }

    /// O embedtv.cc não abre em algumas redes de operadora: aí vem pela função do site.
    private func baixarAgenda() async throws -> [Event] {
        let decoder = JSONDecoder()
        for endereco in ["https://embedtv.cc/api/events", "https://bispotv.pages.dev/api/events"] {
            guard let url = URL(string: endereco),
                  let (dados, _) = try? await URLSession.shared.data(from: url),
                  let lista = try? decoder.decode([Event].self, from: dados) else { continue }
            return lista
        }
        throw URLError(.cannotConnectToHost)
    }
}

import SwiftUI

struct EventsView: View {
    @ObservedObject var model: PlayerModel
    @StateObject private var service = EventsService.shared
    @State private var liga = "Todas"

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)]

    var body: some View {
        Group {
            if service.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Carregando eventos...")
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let error = service.error {
                VStack {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    Text(error)
                        .font(.headline)
                    Text("O serviço de eventos não respondeu. Os canais continuam funcionando normalmente.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Button("Tentar Novamente") {
                        Task { await service.loadEvents(forcar: true) }
                    }
                    .padding()
                    Spacer()
                }
            } else if service.events.isEmpty {
                VStack {
                    Spacer()
                    Text("Nenhum evento no momento")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView { conteudo.padding(18) }
            }
        }
        .task {
            await service.loadEvents()
            // Com a tela aberta, o placar se atualiza sozinho.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await service.loadEvents(forcar: true)
            }
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        let nfl = service.events.filter(\.ehNfl)
        let outros = service.events.filter { !$0.ehNfl }
        let contagem = Dictionary(grouping: outros, by: { $0.league?.name ?? "" }).filter { !$0.key.isEmpty }
        let ligas = contagem.keys.sorted { contagem[$0]!.count > contagem[$1]!.count }
        let filtrados = liga == "Todas" ? outros : outros.filter { $0.league?.name == liga }

        VStack(alignment: .leading, spacing: 22) {
            if !nfl.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "football.fill").foregroundStyle(Tema.acento)
                        Text("NFL").font(.system(size: 17, weight: .medium))
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(nfl.isEmpty ? "Jogos" : "Outros jogos").font(.system(size: 17, weight: .medium))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["Todas"] + ligas, id: \.self) { nome in
                                Button { liga = nome } label: {
                                    Text(nome)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Capsule().fill(liga == nome ? Tema.acento.opacity(0.14) : Color.white.opacity(0.06)))
                                        .overlay(Capsule().strokeBorder(liga == nome ? Tema.acento : .clear, lineWidth: 1))
                                        .foregroundStyle(liga == nome ? Tema.acento : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    grade(filtrados)
                }
            }
        }
    }

    private func grade(_ lista: [Event]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(lista) { event in
                EventCell(event: event) { playEvent(event) }
            }
        }
    }

    private func playEvent(_ event: Event) {
        guard let slug = event.channelSlug else { return }
        model.playChannel(bySlug: slug)
        VodEstado.shared.secao = nil
    }
}

struct EventCell: View {
    let event: Event
    let action: () -> Void

    var body: some View {
        let vivo = event.aoVivo()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(event.league?.name ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Tema.neutro400)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if vivo {
                    HStack(spacing: 5) {
                        Circle().fill(Tema.acento300).frame(width: 6, height: 6)
                        Text("AO VIVO").font(.system(size: 10, weight: .semibold))
                        if !event.tempo.isEmpty { Text(event.tempo).font(.system(size: 10)) }
                    }
                    .foregroundStyle(Tema.acento300)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Tema.acento.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(event.formattedTime)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tema.neutro300)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Tema.neutro900, in: RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(alignment: .center, spacing: 8) {
                escudo(event.teams?.home)
                Group {
                    if event.placar.isEmpty {
                        Text("X").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.neutro500)
                    } else {
                        Text(event.placar.replacingOccurrences(of: " x ", with: "  x  "))
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    }
                }
                .frame(minWidth: 44)
                escudo(event.teams?.away)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(vivo ? Tema.acento900 : Tema.fundo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(vivo ? Tema.acento.opacity(0.6) : Tema.neutro800, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .help(vivo ? "Assistir \(event.title)" : "\(event.title) — o canal fica disponível na hora do jogo")
    }

    private func escudo(_ time: EventTeam?) -> some View {
        VStack(spacing: 5) {
            if let imagem = time?.image, let url = URL(string: imagem) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 36, height: 36)
            }
            Text(time?.name ?? "")
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}
