import AppKit
import Foundation

// Abertura animada do Bispo TV: quadros PNG que o ffmpeg junta num MP4.
// O original tem um vídeo com a marca dele; este é o nosso, nas cores
// Nocturne, com o ícone (../AppIcon.png) e o nome. Rode ./gerar.sh, que faz
// os dois vídeos (deitado e em pé) e copia para os outros apps.
//
//   swift MakeAbertura.swift <largura> <altura> <pasta dos quadros>
//
// Os apps esperam um vídeo sem som que termina parado no logo: quem some com
// ele (fade) é o app.

let args = CommandLine.arguments
guard args.count == 4, let w = Double(args[1]), let h = Double(args[2]) else {
    print("uso: swift MakeAbertura.swift <largura> <altura> <pasta>")
    exit(1)
}
let pasta = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)

let aqui = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
guard let icone = NSImage(contentsOf: aqui.deletingLastPathComponent().appendingPathComponent("AppIcon.png")) else {
    print("AppIcon.png não encontrado")
    exit(1)
}

func cor(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let fundo = cor(0x161826)
let acento = cor(0x9184D9)
let texto = cor(0xE9E9ED)

let fps = 60.0
let duracao = 3.4
let quadros = Int(duracao * fps)

func limitar(_ x: Double) -> Double { min(1, max(0, x)) }
func progresso(_ t: Double, _ de: Double, _ ate: Double) -> Double { limitar((t - de) / (ate - de)) }
func saida(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
/** Passa um pouco do fim e volta: o ícone "assenta". */
func assenta(_ x: Double) -> Double {
    let c = 1.4
    return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
}

func fonteArredondada(_ tamanho: CGFloat, _ peso: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: tamanho, weight: peso)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: tamanho) { return f }
    return base
}

let menor = min(w, h)
let deitado = w > h
let lado = menor * (deitado ? 0.30 : 0.36)          // tamanho do ícone
let tamanhoNome = menor * (deitado ? 0.085 : 0.10)
let blocoAltura = lado + tamanhoNome * 1.6           // ícone + espaço + nome
let topoBloco = (h + blocoAltura) / 2                // em coordenadas do AppKit (y para cima)

for q in 0..<quadros {
    let t = Double(q) / fps
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high

    // Fundo índigo com duas manchas de luz do acento, que andam devagar.
    fundo.setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    let deriva = t / duracao
    let luzes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (CGFloat(w * (0.18 + 0.06 * deriva)), CGFloat(h * 0.78), CGFloat(menor * 0.9), 0.16),
        (CGFloat(w * (0.84 - 0.06 * deriva)), CGFloat(h * 0.22), CGFloat(menor * 0.8), 0.12),
    ]
    for (x, y, r, a) in luzes {
        let g = NSGradient(colors: [acento.withAlphaComponent(a), acento.withAlphaComponent(0)])!
        g.draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }

    // Ícone: entra crescendo e assenta (0,15 s a 1,0 s).
    let pi = progresso(t, 0.15, 1.0)
    let escala = 0.72 + 0.28 * assenta(pi)
    let alfaIcone = saida(progresso(t, 0.15, 0.6))
    let centroX = w / 2
    let centroY = topoBloco - lado / 2
    // Brilho atrás do ícone, que acende junto.
    let brilho = NSGradient(colors: [acento.withAlphaComponent(0.35 * alfaIcone), acento.withAlphaComponent(0)])!
    brilho.draw(fromCenter: NSPoint(x: centroX, y: centroY), radius: 0,
                toCenter: NSPoint(x: centroX, y: centroY), radius: CGFloat(lado * 0.95 * escala), options: [])
    let ladoAgora = lado * escala
    icone.draw(in: NSRect(x: centroX - ladoAgora / 2, y: centroY - ladoAgora / 2, width: ladoAgora, height: ladoAgora),
               from: .zero, operation: .sourceOver, fraction: CGFloat(alfaIcone))

    // Nome: sobe e aparece (0,85 s a 1,5 s).
    let pn = saida(progresso(t, 0.85, 1.5))
    if pn > 0 {
        let atributos: [NSAttributedString.Key: Any] = [
            .font: fonteArredondada(CGFloat(tamanhoNome), .bold),
            .foregroundColor: texto.withAlphaComponent(CGFloat(pn)),
            .kern: tamanhoNome * 0.02,
        ]
        let nome = NSAttributedString(string: "Bispo TV", attributes: atributos)
        let medida = nome.size()
        let y = topoBloco - blocoAltura - (1 - pn) * tamanhoNome * 0.4
        nome.draw(at: NSPoint(x: centroX - medida.width / 2, y: y))
    }

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: pasta.appendingPathComponent(String(format: "%04d.png", q + 1)))
}
print("\(quadros) quadros em \(pasta.path)")
