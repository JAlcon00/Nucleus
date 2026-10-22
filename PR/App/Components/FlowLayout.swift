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

    /// Posición de cada vista y tamaño total, llenando filas de izquierda a derecha.
    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}
