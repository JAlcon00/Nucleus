//
//  FlowLayout.swift
//  PR
//
//  Created by PR.
//
//  Acomoda vistas en filas y salta de línea cuando no caben (chips de músculos, SCRUM-197).
//  Con tamaños de accesibilidad los chips bajan a la siguiente fila en vez de cortarse.
//  Sólo acomoda: no decide qué se muestra.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = DSpace.xs
    /// Separación entre filas; por defecto la misma que entre vistas.
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(subview.sizeThatFits(.unspecified))
            )
        }
    }

    /// Posición de cada vista y tamaño total, llenando filas de izquierda a derecha. Cada
    /// vista queda centrada en vertical dentro de su fila (una etiqueta junto a texto).
    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(index)
            x += size.width + spacing
        }
        var origins = Array(repeating: CGPoint.zero, count: sizes.count)
        var y: CGFloat = 0
        var widest: CGFloat = 0
        for row in rows where !row.isEmpty {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var rowX: CGFloat = 0
            for index in row {
                origins[index] = CGPoint(x: rowX, y: y + (rowHeight - sizes[index].height) / 2)
                rowX += sizes[index].width + spacing
            }
            widest = max(widest, rowX - spacing)
            y += rowHeight + (lineSpacing ?? spacing)
        }
        let height = max(y - (lineSpacing ?? spacing), 0)
        return (origins, CGSize(width: widest, height: height))
    }
}
