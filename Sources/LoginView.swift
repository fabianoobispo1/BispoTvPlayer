import SwiftUI
import AppKit

/// A raiz da janela: sem conta, a tela de entrar; com senha temporária, a de
/// trocar; com conta, o app.
struct RaizView: View {
    @ObservedObject private var conta = Conta.shared
    @ObservedObject private var versao = VersaoMinima.shared

    var body: some View {
        Group {
            if versao.desatualizado {
                // Bispo TV: abaixo da versão mínima do painel, nada além disto.
                TelaAtualizar()
            } else if let info = conta.info {
                if info.situacao == "bloqueada" {
                    RenovarAssinaturaView()
                } else if info.trocarSenha {
                    TrocarSenhaView()
                } else {
                    // Bispo TV: os avisos do painel numa faixa no topo da janela.
                    VStack(spacing: 0) {
                        FaixaDeAvisos()
                        ContentView()
                    }
                    .onAppear { Avisos.shared.iniciar() }
                }
            } else {
                LoginView()
            }
        }
        .task { await conta.conferir() }
        .onAppear { VersaoMinima.shared.iniciar() }
        // Nocturne: o roxo do Bispo TV no lugar do azul do sistema, em tudo.
        .tint(Tema.acento)
        .preferredColorScheme(.dark)
    }
}

private struct RenovarAssinaturaView: View {
    @Environment(\.openURL) private var abrir
    private let assinar = URL(string: "https://bispotv.pages.dev/assinar")!

    var body: some View {
        FundoNocturne()
            .overlay {
                VStack(spacing: 16) {
                    Text("Conta bloqueada").font(.title2.weight(.medium))
                    Text("Renove em bispotv.pages.dev/assinar")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Abrir página de renovação") { abrir(assinar) }
                        .buttonStyle(BotaoContornado())
                    Button("Sair da conta") { Task { await Conta.shared.sair() } }
                        .buttonStyle(.link)
                }
                .padding(32)
                .background(RoundedRectangle(cornerRadius: 14).fill(Tema.superficie))
            }
    }
}

/// "Atualize o Bispo TV": a versão instalada ficou abaixo da mínima do painel.
/// O botão abre o DMG já baixado pelo atualizador (e fecha o app, para o novo
/// poder substituir o antigo) ou, sem ele, baixa pelo navegador.
private struct TelaAtualizar: View {
    @ObservedObject private var versao = VersaoMinima.shared
    @ObservedObject private var atualizacao = Atualizacao.shared
    @Environment(\.openURL) private var abrir

    var body: some View {
        CartaoConta(titulo: "Atualize o Bispo TV",
                    subtitulo: "Esta versão (\(versao.atual)) não funciona mais. Atualize para a \(versao.minima ?? "") ou mais nova para continuar assistindo. Sua conta, favoritos e o que ficou pela metade continuam iguais.") {
            Button("Atualizar agora") {
                if let nova = atualizacao.disponivel {
                    atualizacao.atualizar(nova)
                } else {
                    abrir(versao.baixar)
                }
            }
            .buttonStyle(BotaoContornado())
            Text("Ou baixe em \(versao.baixar.absoluteString.replacingOccurrences(of: "https://", with: "")) e arraste para Aplicativos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            PlayerModel.shared.pararTudo()
            // Já começa a baixar o DMG, para o botão abrir o instalador pronto.
            atualizacao.procurar(manual: true)
        }
    }
}

/// O cartão escuro centralizado das telas de conta, com o ícone e o nome.
private struct CartaoConta<Conteudo: View>: View {
    let titulo: String
    let subtitulo: String
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        ZStack {
            FundoNocturne()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 52, height: 52)
                    (Text("Bispo ") + Text("TV").foregroundColor(Tema.acento))
                        .font(.system(size: 22, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).font(.system(size: 22, weight: .medium))
                    Text(subtitulo).font(.callout).foregroundStyle(.secondary)
                }
                conteudo
            }
            .padding(28)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 14).fill(Tema.superficie))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tema.neutro800))
        }
        .frame(minWidth: 520, minHeight: 560)
        .preferredColorScheme(.dark)
    }
}

private struct Campo: View {
    let rotulo: String
    @Binding var texto: String
    var segredo = false
    var dica: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rotulo).font(.callout.weight(.medium))
            Group {
                if segredo { SecureField("", text: $texto) } else { TextField("", text: $texto) }
            }
            .textFieldStyle(.plain)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Tema.fundo))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.neutro800))
            if let dica { Text(dica).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct BotaoPrincipal: View {
    let titulo: String
    let ocupado: Bool
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text(ocupado ? "Aguarde…" : titulo)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(BotaoContornado())
        .keyboardShortcut(.defaultAction)
        .disabled(ocupado)
    }
}

private struct MensagemErro: View {
    let texto: String
    var body: some View {
        Text(texto)
            .font(.callout)
            .foregroundStyle(Tema.erro)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.12)))
    }
}

/// Conta nova e senha esquecida são pelo WhatsApp (o robô do BispoTvApi). Os
/// endereços passam pelo site, que redireciona: trocar o número não pede versão nova.
private let pedirAcesso = URL(string: "https://bispotv.pages.dev/whatsapp")!

struct LoginView: View {
    @State private var email = ""
    @State private var senha = ""
    @State private var erro: String?
    @State private var ocupado = false
    @State private var assinaturaBloqueada = false
    /// Conta no limite: os aparelhos para escolher qual sai.
    @State private var cheia: [Conta.Aparelho] = []
    @Environment(\.openURL) private var abrir

    var body: some View {
        if assinaturaBloqueada { RenovarAssinaturaView() }
        else if cheia.isEmpty { formulario }
        else { escolherAparelho }
    }

    private var escolherAparelho: some View {
        CartaoConta(titulo: "Limite de aparelhos",
                    subtitulo: "Esta conta já está no limite de aparelhos. Escolha qual desconectar para entrar aqui; ele precisará entrar de novo para usar.") {
            ForEach(cheia) { a in
                HStack(spacing: 12) {
                    Image(systemName: Self.icones[a.plataforma] ?? "display")
                        .font(.system(size: 20)).foregroundStyle(Tema.acento).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.nome).font(.system(size: 14, weight: .medium))
                        Text("Usado \(Self.haQuanto(a.usadoEm))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Desconectar") { enviar(desconectar: a.id) }
                        .buttonStyle(BotaoContornado())
                        .disabled(ocupado)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Tema.fundo))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.neutro800))
            }
            if let erro { MensagemErro(texto: erro) }
            Button("Voltar") { cheia = []; erro = nil }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
        }
    }

    private static let icones = ["tvbox": "tv", "windows": "pc", "mac": "laptopcomputer", "cell": "iphone", "site": "globe"]

    private static func haQuanto(_ data: Date?) -> String {
        guard let data else { return "há algum tempo" }
        let min = max(0, Int(Date().timeIntervalSince(data) / 60))
        switch min {
        case ..<5: return "agora há pouco"
        case ..<60: return "há \(min) min"
        case ..<2880: return "há \(min / 60) h"
        default: return "há \(min / 1440) dias"
        }
    }

    private var formulario: some View {
        CartaoConta(titulo: "Entrar",
                    subtitulo: "A mesma conta vale no site, no celular, na TV Box, no Windows e no Mac.") {
            Campo(rotulo: "E-mail", texto: $email)
            Campo(rotulo: "Senha", texto: $senha, segredo: true)
            if let erro { MensagemErro(texto: erro) }
            BotaoPrincipal(titulo: "Entrar", ocupado: ocupado) { enviar() }
            Text("Esqueceu a senha? [Mande SENHA no WhatsApp](https://bispotv.pages.dev/senha) e receba um link para criar outra.")
                .font(.caption).foregroundStyle(.secondary)
            Divider().overlay(Tema.neutro800).padding(.top, 4)
            VStack(spacing: 10) {
                Text("Ainda não tem conta? O acesso é criado pelo WhatsApp, em um minuto.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { abrir(pedirAcesso) } label: {
                    Label("Pedir acesso pelo WhatsApp", systemImage: "message")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tema.texto)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.neutro800))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func enviar(desconectar: Int? = nil) {
        erro = nil
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                try await Conta.shared.entrar(email: email.trimmingCharacters(in: .whitespaces), senha: senha, desconectar: desconectar)
                cheia = []
            } catch let falha as Conta.Erro where !falha.aparelhos.isEmpty {
                cheia = falha.aparelhos
            } catch let falha as Conta.Erro where falha.status == 403 && falha.situacao == "bloqueada" {
                assinaturaBloqueada = true
            } catch {
                erro = error.localizedDescription
            }
        }
    }
}

struct TrocarSenhaView: View {
    @State private var atual = ""
    @State private var nova = ""
    @State private var erro: String?
    @State private var ocupado = false

    var body: some View {
        CartaoConta(titulo: "Crie uma senha nova",
                    subtitulo: "Você entrou com uma senha temporária. Escolha a sua para continuar.") {
            Campo(rotulo: "Senha temporária", texto: $atual, segredo: true)
            Campo(rotulo: "Senha nova", texto: $nova, segredo: true, dica: "Pelo menos 8 caracteres.")
            if let erro { MensagemErro(texto: erro) }
            BotaoPrincipal(titulo: "Salvar senha", ocupado: ocupado) {
                erro = nil
                ocupado = true
                Task {
                    defer { ocupado = false }
                    do { try await Conta.shared.trocarSenha(atual: atual, nova: nova) } catch { erro = error.localizedDescription }
                }
            }
            Button("Sair") { Task { await Conta.shared.sair() } }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
        }
    }
}
