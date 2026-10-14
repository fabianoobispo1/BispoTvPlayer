import SwiftUI
import AppKit

/// As cores e as peças de vidro do app, as mesmas da TV Box.
///
/// Bispo TV: Nocturne, o tema do projeto "Renovação de design e ícone" no
/// Claude Design (as mesmas cores do site, da TV Box, do Windows e do
/// celular). Fundo índigo-escuro, um acento roxo-azulado só para o que
/// importa e botões contornados, nunca preenchidos. A estrutura (vidro, foco,
/// selos) é a do original; as cores são as nossas.
enum Tema {
    static let fundo = Color(hex: 0x161826)
    static let superficie = Color(hex: 0x232532)
    static let texto = Color(hex: 0xE9E9ED)
    static let secao = Color(hex: 0x262A60)

    static let acento = Color(hex: 0x9184D9)
    static let acento200 = Color(hex: 0xE7E5FE)
    static let acento300 = Color(hex: 0xD2CEFD)
    static let acento400 = Color(hex: 0xB5ABFC)
    static let acento900 = Color(hex: 0x2B2741)

    static let neutro300 = Color(hex: 0xCFD3E5)
    static let neutro400 = Color(hex: 0xB2B6CA)
    static let neutro500 = Color(hex: 0x9397AB)
    static let neutro800 = Color(hex: 0x3F424D)
    static let neutro900 = Color(hex: 0x292B31)

    static let divisor = Color(hex: 0xE9E9ED).opacity(0.16)
    static let erro = Color(hex: 0xFCA5A5)

    /// O "ao vivo": o lilás claro do acento (o Nocturne não usa vermelho).
    static let aoVivo = acento400
    static let cartao = Color.white.opacity(0.07)
    static let textoSecundario = neutro400
    static let textoApagado = Color.white.opacity(0.4)

    /// Altura da barra do topo: o conteúdo das telas começa abaixo dela.
    static let alturaDaBarra: CGFloat = 64
    /// Margem lateral das telas, a mesma das fileiras e do destaque.
    static let margem: CGFloat = 40

    /// As cores das categorias nos cartões do On Demand: todas no acento,
    /// como pede o Nocturne (um destaque só).
    static let corFilmes = acento
    static let corSeries = acento
    static let corAnimes = acento
    static let corDoramas = acento
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Fundo

/// O fundo do app (Nocturne): índigo no canto de cima, um azul fundo no de
/// baixo, como no site. Desenhado, não baixado: acompanha qualquer tamanho de
/// janela sem esticar pixel.
struct FundoDoApp: View {
    var body: some View {
        ZStack {
            Tema.fundo
            RadialGradient(colors: [Tema.acento900, .clear], center: .topLeading,
                           startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Tema.secao.opacity(0.6), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// O mesmo fundo, com o nome que as telas do Bispo TV já usavam.
typealias FundoNocturne = FundoDoApp

/// Botão contornado do Nocturne: borda e texto no acento, fundo só ao passar
/// o mouse ou apertar.
struct BotaoContornado: ButtonStyle {
    var cor: Color = Tema.acento

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(cor)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(cor.opacity(configuration.isPressed ? 0.22 : 0.08),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(cor, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Vidro

/// Liquid Glass no macOS 26 em diante; antes dele, o material translúcido de
/// sempre. O app roda a partir do macOS 15, então toda peça de vidro passa
/// por aqui em vez de chamar `glassEffect` direto.
extension View {
    /// Vidro numa forma qualquer.
    @ViewBuilder
    func vidro<Forma: Shape>(_ forma: Forma, tinta: Color? = nil, interativo: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.vidroComo(tinta: tinta, interativo: interativo), in: forma)
        } else {
            self.background {
                ZStack {
                    forma.fill(.ultraThinMaterial)
                    if let tinta { forma.fill(tinta.opacity(0.35)) }
                    forma.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
        }
    }

    /// Vidro em cápsula: botões, pílulas e a barra do topo.
    func vidroCapsula(tinta: Color? = nil, interativo: Bool = false) -> some View {
        vidro(Capsule(), tinta: tinta, interativo: interativo)
    }

    /// Vidro em retângulo arredondado: painéis e cartões flutuantes.
    func vidroPainel(raio: CGFloat = 18, tinta: Color? = nil) -> some View {
        vidro(RoundedRectangle(cornerRadius: raio, style: .continuous), tinta: tinta)
    }

    @available(macOS 26.0, *)
    private static func vidroComo(tinta: Color?, interativo: Bool) -> Glass {
        var vidro = Glass.regular
        if let tinta { vidro = vidro.tint(tinta.opacity(0.6)) }
        if interativo { vidro = vidro.interactive() }
        return vidro
    }

    /// Marca a peça para se fundir às vizinhas quando o vidro anda (a aba
    /// escolhida deslizando de uma aba para a outra).
    @ViewBuilder
    func vidroID(_ id: String, em espaco: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: espaco)
        } else {
            self.matchedGeometryEffect(id: id, in: espaco)
        }
    }
}

/// Agrupa peças de vidro vizinhas para que se misturem como uma só superfície
/// (`GlassEffectContainer`). Antes do macOS 26 só devolve o conteúdo.
struct GrupoDeVidro<Conteudo: View>: View {
    var espacamento: CGFloat = 12
    @ViewBuilder let conteudo: () -> Conteudo

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: espacamento) { conteudo() }
        } else {
            conteudo()
        }
    }
}

/// Botão de vidro: `.glass` no macOS 26, cápsula de material antes dele. O
/// proeminente é contornado no acento (Nocturne), em qualquer macOS.
struct BotaoDeVidro: ButtonStyle {
    var proeminente = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(proeminente ? Tema.acento : Tema.texto)
            .background {
                if proeminente {
                    Capsule().fill(Tema.acento.opacity(configuration.isPressed ? 0.22 : 0.10))
                    Capsule().strokeBorder(Tema.acento, lineWidth: 1)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension View {
    /// O botão de vidro do sistema quando existe; o nosso antes do macOS 26.
    @ViewBuilder
    func botaoDeVidro(proeminente: Bool = false) -> some View {
        if proeminente {
            // Bispo TV: nada de botão preenchido, nem no vidro do macOS 26.
            self.buttonStyle(BotaoDeVidro(proeminente: true))
        } else if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(BotaoDeVidro(proeminente: proeminente))
        }
    }
}

// MARK: - Foco

/// O realce de foco da TV, no mouse: o cartão sob o ponteiro cresce um pouco e
/// ganha a borda e o brilho do acento (Nocturne). O teclado (Tab) mostra o mesmo.
struct CartaoEmFoco: ButtonStyle {
    var raio: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Modificador(configuration: configuration, raio: raio)
    }

    private struct Modificador: View {
        let configuration: Configuration
        let raio: CGFloat
        @State private var sobre = false
        @Environment(\.isFocused) private var focado

        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: raio + 3, style: .continuous)
                        .strokeBorder(Tema.acento, lineWidth: 2.5)
                        .padding(-4)
                        .shadow(color: Tema.acento.opacity(0.55), radius: 8)
                        .opacity(sobre || focado ? 1 : 0)
                }
                .scaleEffect(configuration.isPressed ? 0.98 : (sobre ? 1.03 : 1))
                .animation(.easeOut(duration: 0.14), value: sobre)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { sobre = $0 }
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Imagens

/// Imagens da rede guardadas na memória enquanto o app está aberto.
///
/// `AsyncImage` baixa de novo toda vez que a célula volta à tela: rolar uma
/// fileira para lá e para cá refazia cada pedido. Aqui cada endereço é
/// baixado uma vez (o cache do URLSession ainda guarda em disco).
@MainActor
final class ImagensRemotas: ObservableObject {
    static let shared = ImagensRemotas()

    private let cache = NSCache<NSString, NSImage>()
    private var pedidas = Set<String>()
    @Published private(set) var versao = 0
    private let sessao: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("imagens"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    private init() { cache.countLimit = 600 }

    func imagem(_ endereco: String) -> NSImage? {
        if let pronta = cache.object(forKey: endereco as NSString) { return pronta }
        pedir(endereco)
        return nil
    }

    private func pedir(_ endereco: String) {
        guard !pedidas.contains(endereco), let url = URL(string: endereco) else { return }
        pedidas.insert(endereco)
        let sessao = self.sessao
        Task {
            guard let (dados, _) = try? await sessao.data(from: url),
                  let imagem = NSImage(data: dados) else { return }
            cache.setObject(imagem, forKey: endereco as NSString)
            versao &+= 1
        }
    }
}

/// Uma imagem da rede que ocupa o quadro inteiro, com a reserva até chegar.
struct ImagemRemota<Reserva: View>: View {
    let endereco: String?
    var modo: ContentMode = .fill
    @ViewBuilder var reserva: () -> Reserva
    @ObservedObject private var imagens = ImagensRemotas.shared

    var body: some View {
        if let endereco, !endereco.isEmpty, let imagem = imagens.imagem(endereco) {
            Image(nsImage: imagem)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: modo)
                .transition(.opacity)
        } else {
            reserva()
        }
    }
}

extension ImagemRemota where Reserva == Color {
    init(_ endereco: String?, modo: ContentMode = .fill) {
        self.init(endereco: endereco, modo: modo) { Color.clear }
    }
}

// MARK: - Selos

/// "AO VIVO" em lilás sobre índigo (Nocturne), com o placar ou o tempo de jogo quando há.
struct SeloAoVivo: View {
    var texto = "AO VIVO"

    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Tema.acento200)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Tema.acento900, in: Capsule())
            .overlay(Capsule().strokeBorder(Tema.aoVivo, lineWidth: 1))
    }
}

/// A barra fina de progresso das capas e dos cartões: o acento sobre trilho.
struct BarraDeProgresso: View {
    let fracao: Double
    var altura: CGFloat = 4
    var cor: Color = Tema.acento

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(cor)
                    .frame(width: max(altura, geo.size.width * min(max(fracao, 0), 1)))
            }
        }
        .frame(height: altura)
    }
}

/// O relógio do topo, como na TV: horas e minutos, sem segundos.
struct Relogio: View {
    var tamanho: CGFloat = 17

    var body: some View {
        TimelineView(.everyMinute) { contexto in
            Text(contexto.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: tamanho, weight: .medium).monospacedDigit())
                .foregroundStyle(Tema.texto)
        }
    }
}
