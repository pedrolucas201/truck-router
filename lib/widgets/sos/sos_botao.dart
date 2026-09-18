import 'package:flutter/material.dart';

import '../../models/sos_request.dart';

/// Botão do S.O.S. na navegação (opção B, escolhida pelo Beto em 18/09): o
/// pedido chega ABERTO ("Pedro pede ajuda · Pneu · a 7 km"), recolhe pro
/// redondo SOS depois de 10 s (quem controla é a tela) e fica no meio da
/// lateral esquerda, que é o lado livre (os botões da nav ficam à direita).
/// Tocar, aberto ou fechado, abre a ficha.
class SosBotao extends StatelessWidget {
  final SosRequest sos;
  final double distM;
  final bool aberto;
  final int total; // pedidos ativos perto; >1 ganha o número no canto
  final VoidCallback onTap;

  const SosBotao({
    super.key,
    required this.sos,
    required this.distM,
    required this.aberto,
    required this.total,
    required this.onTap,
  });

  static const _vermelho = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final km = sosDistText(distM);
    final redondo = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: aberto ? Colors.white : _vermelho,
        shape: BoxShape.circle,
        border: aberto ? null : Border.all(color: Colors.white, width: 4),
      ),
      alignment: Alignment.center,
      child: Text('SOS',
          style: TextStyle(
              color: aberto ? _vermelho : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900)),
    );
    final corpo = AnimatedSize(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.fromLTRB(aberto ? 6 : 0, aberto ? 6 : 0, aberto ? 18 : 0, aberto ? 6 : 0),
        decoration: BoxDecoration(
          color: _vermelho,
          borderRadius: BorderRadius.circular(40),
          border: aberto ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: const [
            BoxShadow(color: Color(0x38C62828), spreadRadius: 8),
            BoxShadow(color: Color(0x4D000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          redondo,
          if (aberto) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${sos.nome} pede ajuda',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                Text('${sos.tipo.label} · a $km',
                    style: const TextStyle(color: Color(0xFFFFE1E1), fontSize: 14)),
              ]),
            ),
          ],
        ]),
      ),
    );
    return Semantics(
      button: true,
      label: 'Pedido de ajuda: ${sos.nome}, ${sos.tipo.label}, a $km',
      child: GestureDetector(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            corpo,
            if (total > 1)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                  child: Text('$total',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
          if (!aberto)
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
              ),
              alignment: Alignment.center,
              child: Text(km,
                  style: const TextStyle(
                      color: _vermelho, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}
