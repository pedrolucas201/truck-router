import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/voice_settings.dart';

/// Escolha da voz do guia, DE OUVIDO: a API do Android não diz o gênero da
/// voz, então nada de rótulo "masculina/feminina" — tocar numa opção fala a
/// amostra com ela e o motorista fica com a que gostar. Nome de engine nunca
/// aparece na tela.
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  static const _sample = 'Em duzentos metros, vire à direita.';

  late final FlutterTts _tts;
  List<Map<String, String>> _voices = const [];
  bool _loading = true;
  String? _selectedName; // null = voz padrão do aparelho
  String _tone = 'normal';

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _tts.setLanguage('pt-BR');
    _tts.setSpeechRate(0.5); // mesmo rate da navegação, senão a amostra mente
    _init();
  }

  Future<void> _init() async {
    final saved = await VoiceSettings.load();
    List<Map<String, String>> voices = const [];
    try {
      voices = VoiceSettings.ptVoices(await _tts.getVoices);
    } catch (_) {} // sem lista, sobram Padrão + tons — a tela continua útil
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _selectedName = saved.name;
      _tone = saved.tone;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _preview() async {
    final v = _voices.where((v) => v['name'] == _selectedName).firstOrNull;
    if (v != null) {
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    } else {
      await _tts.clearVoice();
    }
    await _tts.setPitch(VoiceSettings.tones[_tone] ?? 1.0);
    await _tts.stop();
    await _tts.speak(_sample);
  }

  Future<void> _choose({String? name, String? tone}) async {
    setState(() {
      if (tone != null) _tone = tone;
      // name só muda quando o toque foi numa voz (tone == null).
      if (tone == null) _selectedName = name;
    });
    final v = _voices.where((v) => v['name'] == _selectedName).firstOrNull;
    await VoiceSettings.save(
        name: v?['name'], locale: v?['locale'], tone: _tone);
    await _preview();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Voz do guia')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('Toque para ouvir. A escolhida fica valendo.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                _voiceTile(
                  label: 'Padrão do aparelho',
                  selected: _selectedName == null,
                  onTap: () => _choose(name: null),
                ),
                for (final (i, v) in _voices.indexed)
                  _voiceTile(
                    label: 'Voz ${i + 1}',
                    selected: _selectedName == v['name'],
                    onTap: () => _choose(name: v['name']),
                  ),
                const SizedBox(height: 24),
                Text('Tom de voz',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (key, label) in const [
                      ('normal', 'Normal'),
                      ('et', 'E.T. 👽'),
                      ('robo', 'Robô 🤖'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _tone == key,
                        selectedColor: primary.withAlpha(40),
                        onSelected: (_) => _choose(tone: key),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _voiceTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: selected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: primary, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(Icons.record_voice_over,
            color: selected ? primary : Colors.grey.shade400),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? primary : null)),
        trailing: Icon(Icons.volume_up, size: 20, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }
}
