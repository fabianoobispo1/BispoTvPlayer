import SwiftUI
import AppKit

/// A raiz da janela: sem conta, a tela de entrar; com senha temporária, a de
/// trocar; com conta, o app.
struct RaizView: View {
    @ObservedObject private var conta = Conta.shared

    var body: some View {
        Group {
            if let info = conta.info {
                if info.trocarSenha { TrocarSenhaView() } else { ContentView() }
            } else {
                LoginView()
            }
        }
        .task { await conta.conferir() }
    }
}

/// O cartão escuro centralizado das telas de conta, com o ícone e o nome.
private struct CartaoConta<Conteudo: View>: View {
    let titulo: String
    let subtitulo: String
    @ViewBuilder let conteudo: Conteudo

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.14), Color(red: 0.04, green: 0.04, blue: 0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 52, height: 52)
                    Text("Bispo TV").font(.system(size: 22, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(titulo).font(.system(size: 22, weight: .semibold))
                    Text(subtitulo).font(.callout).foregroundStyle(.secondary)
                }
                conteudo
            }
            .padding(28)
            .frame(width: 400)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.09).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
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
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.12)))
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
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.93, green: 0.28, blue: 0.6)],
                                           startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(ocupado)
    }
}

private struct MensagemErro: View {
    let texto: String
    var body: some View {
        Text(texto)
            .font(.callout)
            .foregroundStyle(Color(red: 0.99, green: 0.65, blue: 0.69))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.12)))
    }
}

struct LoginView: View {
    private enum Modo: String, CaseIterable { case entrar = "Entrar", criar = "Criar conta" }

    @State private var modo: Modo = .entrar
    @State private var email = ""
    @State private var senha = ""
    @State private var nome = ""
    @State private var erro: String?
    @State private var ocupado = false

    var body: some View {
        CartaoConta(titulo: modo == .criar ? "Criar conta" : "Entrar",
                    subtitulo: modo == .criar ? "Grátis. A mesma conta vale no site, na TV Box, no Windows e no Mac."
                                              : "Use a conta do Bispo TV para assistir.") {
            Picker("", selection: $modo) {
                ForEach(Modo.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: modo) { erro = nil }

            if modo == .criar { Campo(rotulo: "Nome (opcional)", texto: $nome) }
            Campo(rotulo: "E-mail", texto: $email)
            Campo(rotulo: "Senha", texto: $senha, segredo: true, dica: modo == .criar ? "Pelo menos 8 caracteres." : nil)
            if let erro { MensagemErro(texto: erro) }
            BotaoPrincipal(titulo: modo == .criar ? "Criar conta" : "Entrar", ocupado: ocupado) { enviar() }
            if modo == .entrar {
                Text("Esqueceu a senha? Fale com quem administra o Bispo TV para receber uma senha temporária.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func enviar() {
        erro = nil
        ocupado = true
        Task {
            defer { ocupado = false }
            do {
                let e = email.trimmingCharacters(in: .whitespaces)
                if modo == .criar { try await Conta.shared.cadastrar(email: e, senha: senha, nome: nome) }
                else { try await Conta.shared.entrar(email: e, senha: senha) }
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
