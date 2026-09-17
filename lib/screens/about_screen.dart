import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/field_log.dart';

/// "Sobre": versão do app e CRÉDITO DAS FONTES DE DADOS.
///
/// Não é vitrine: é obrigação de licença. Duas das fontes que o app usa hoje
/// exigem atribuição por escrito, e sem esta tela o uso está fora da licença —
/// o mesmo problema que a gente está tentando sair.
///
///  - **OpenStreetMap (ODbL)**: dá o sentido da pista a 15.568 radares
///    (`osm_geom`). Exige crédito a "OpenStreetMap contributors" para obra
///    derivada. Já era pendência ANTES do MapAtlas.
///  - **MapAtlas (CC BY 4.0)**: cobertura de radar. Licença livre inclusive pra
///    uso comercial, com uma condição: crédito com link.
///
/// As fontes públicas (DNIT, ANTT, DER-SP, CET-SP, ARTESP) não exigem
/// atribuição, mas entram porque dizer de onde vem o dado é o que sustenta a
/// confiança do motorista no alerta.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _fontes = <({String nome, String papel, String url})>[
    (
      nome: 'OpenStreetMap',
      papel: 'Geometria das vias, usada para descobrir o sentido do radar',
      url: 'https://www.openstreetmap.org/copyright',
    ),
    (
      nome: 'MapAtlas',
      papel: 'Localização de radares',
      url: 'https://mapatlas.eu',
    ),
    (
      nome: 'DNIT e ANTT',
      papel: 'Radares de rodovia federal, com sentido e limite de caminhão',
      url: 'https://servicos.dnit.gov.br/dadosabertos',
    ),
    (
      nome: 'DER-SP, CET-SP e ARTESP',
      papel: 'Radares e limites de São Paulo',
      url: 'https://dadosabertos.artesp.sp.gov.br',
    ),
    (
      nome: 'HERE',
      papel: 'Rotas para caminhão e clima na estrada',
      url: 'https://www.here.com',
    ),
  ];

  Future<void> _abrir(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e, st) {
      // Link que não abre não pode derrubar a tela: o crédito em texto já
      // cumpre a licença, o link é conveniência.
      FieldLog.error('about_link', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/brand/icone.png',
                  width: 56, height: 56, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No Trecho',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text('Versão ${FieldLog.appVersion}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 28),
          Text('De onde vêm os dados',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Os alertas de radar, restrição e pedágio são montados a partir '
            'destas fontes, mais as correções que os próprios motoristas fazem '
            'no app.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          for (final f in _fontes)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: ListTile(
                title: Text(f.nome,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(f.papel),
                trailing: Icon(Icons.open_in_new, size: 18, color: cor.primary),
                onTap: () => _abrir(f.url),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Dados do OpenStreetMap sob licença ODbL e do MapAtlas sob '
            'CC BY 4.0. Radar marcado por motorista fica no aparelho e na '
            'rede do app.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
