import Foundation

/// Bispo TV: a versão mínima do app, definida no painel da API
/// (/painel/versoes). Abaixo dela, a janela mostra "Atualize o Bispo TV" no
/// lugar de tudo e não se assiste até atualizar.
///
/// Confere ao abrir e de 5 em 5 minutos. Sem rede ou sem resposta, não
/// bloqueia: o app não pode parar por falta de internet.
@MainActor
final class VersaoMinima: ObservableObject {
    static let shared = VersaoMinima()

    @Published private(set) var minima: String?
    @Published private(set) var baixar = URL(string: "https://bispotv.pages.dev/mac")!

    private var iniciada = false

    var atual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var desatualizado: Bool {
        guard let minima else { return false }
        return Self.comparar(minima, atual) > 0
    }

    func iniciar() {
        guard !iniciada else { return }
        iniciada = true
        Task { [weak self] in
            while let self {
                await self.conferir()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func conferir() async {
        var partes = URLComponents(url: Conta.api.appendingPathComponent("versao"), resolvingAgainstBaseURL: false)!
        partes.queryItems = [URLQueryItem(name: "plataforma", value: "mac")]
        guard let url = partes.url,
              let (dados, resposta) = try? await URLSession.shared.data(from: url),
              (resposta as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any] else { return }
        minima = json["minima"] as? String
        if let b = json["baixar"] as? String, b.hasPrefix("https://"), let u = URL(string: b) { baixar = u }
    }

    /// "2.5.10" > "2.5.9": número a número. Positivo se a > b.
    static func comparar(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let d = (i < pa.count ? pa[i] : 0) - (i < pb.count ? pb[i] : 0)
            if d != 0 { return d }
        }
        return 0
    }
}
