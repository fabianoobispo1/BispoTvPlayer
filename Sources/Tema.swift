import SwiftUI

/// Nocturne, o tema do Bispo TV (projeto "Renovação de design e ícone" no
/// Claude Design): as mesmas cores do site e da TV Box. Fundo índigo-escuro,
/// um acento roxo-azulado só para o que importa, botões contornados.
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
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// O fundo das telas que não são vídeo: índigo no canto de cima, um azul
/// fundo no de baixo, como no site.
struct FundoNocturne: View {
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
