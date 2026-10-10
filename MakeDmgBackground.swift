import AppKit

// Fundo da janela do DMG: título, instrução e uma seta do app para a pasta
// Aplicativos. As posições batem com as de dmg_settings.py (em pontos, com a
// origem no canto de cima); mudou lá, muda aqui.
//
//   swift MakeDmgBackground.swift <saída.png> <escala>

let largura: CGFloat = 660
let altura: CGFloat = 440
let iconeApp = NSPoint(x: 175, y: 205)
let iconeAplicativos = NSPoint(x: 485, y: 205)
let iconeLicencas = NSPoint(x: 585, y: 360)

let argumentos = CommandLine.arguments
let saida = argumentos.count > 1 ? argumentos[1] : "dmg-fundo.png"
let escala = argumentos.count > 2 ? CGFloat(Double(argumentos[2]) ?? 1) : 1

// As mesmas cores do ícone.
let fundo = NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.976, alpha: 1)
let marinho = NSColor(calibratedRed: 0.106, green: 0.176, blue: 0.365, alpha: 1)
let cinza = NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.53, alpha: 1)
let turquesa = NSColor(calibratedRed: 0.40, green: 0.85, blue: 0.82, alpha: 1)
let roxo = NSColor(calibratedRed: 0.52, green: 0.45, blue: 0.93, alpha: 1)
let rosa = NSColor(calibratedRed: 0.86, green: 0.40, blue: 0.85, alpha: 1)

func fonte(_ tamanho: CGFloat, _ peso: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: tamanho, weight: peso)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: tamanho) {
        return f
    }
    return base
}

/// Converte do sistema do Finder (origem em cima) para o do AppKit (origem embaixo).
func y(_ topo: CGFloat) -> CGFloat { altura - topo }

func texto(_ s: String, _ f: NSFont, _ cor: NSColor, centroX: CGFloat? = nil,
           esquerda: CGFloat? = nil, direita: CGFloat? = nil, topo: CGFloat) {
    let t = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: cor])
    let tam = t.size()
    let x = esquerda ?? direita.map { $0 - tam.width } ?? ((centroX ?? 0) - tam.width / 2)
    t.draw(at: NSPoint(x: x, y: y(topo) - tam.height))
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(largura * escala), pixelsHigh: Int(altura * escala),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("sem bitmap") }
rep.size = NSSize(width: largura, height: altura)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

fundo.setFill()
NSRect(x: 0, y: 0, width: largura, height: altura).fill()

// Faixa de cor no topo, no degradê do logo.
NSGradient(colors: [turquesa, roxo, rosa])!
    .draw(in: NSRect(x: 0, y: y(6), width: largura, height: 6), angle: 0)

texto("Bispo TV", fonte(30, .bold), marinho, centroX: largura / 2, topo: 34)
texto("Arraste o Bispo TV para a pasta Aplicativos", fonte(15, .medium), cinza,
      centroX: largura / 2, topo: 76)

// Seta do app para Aplicativos, com o mesmo degradê.
let inicio = iconeApp.x + 80
let fim = iconeAplicativos.x - 80
let meio = y(iconeApp.y)
let seta = NSBezierPath()
seta.lineWidth = 7
seta.lineCapStyle = .round
seta.lineJoinStyle = .round
seta.move(to: NSPoint(x: inicio, y: meio))
seta.line(to: NSPoint(x: fim, y: meio))
seta.move(to: NSPoint(x: fim - 18, y: meio + 16))
seta.line(to: NSPoint(x: fim, y: meio))
seta.line(to: NSPoint(x: fim - 18, y: meio - 16))
NSGraphicsContext.saveGraphicsState()
let contorno = seta.copy() as! NSBezierPath
let caminho = contorno.cgPath.copy(strokingWithWidth: 7, lineCap: .round, lineJoin: .round, miterLimit: 10)
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(caminho)
ctx.clip()
NSGradient(colors: [turquesa, roxo, rosa])!
    .draw(in: NSRect(x: inicio - 10, y: meio - 20, width: fim - inicio + 20, height: 40), angle: 0)
NSGraphicsContext.restoreGraphicsState()

// Rodapé: requisito à esquerda e a indicação da pasta de licenças.
texto("Requer Mac com chip Apple e macOS 15 ou mais novo", fonte(12, .regular), cinza,
      esquerda: 28, topo: 412)
texto("Licenças do FFmpeg e das bibliotecas  →", fonte(12, .regular), cinza,
      direita: iconeLicencas.x - 62, topo: iconeLicencas.y - 9)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("sem png") }
try png.write(to: URL(fileURLWithPath: saida))
