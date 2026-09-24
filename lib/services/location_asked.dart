import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Marca de "já pedimos localização NESTA instalação". Compartilhada entre o
/// boot do mapa e o onboarding: o Android promove a SEGUNDA negação a
/// permanente, então quem pede primeiro carimba, e o outro não pede de novo.
///
/// Guarda a hora da instalação junto porque o Auto Backup restaura as prefs em
/// reinstalação (aparelho do Pedro: `presence_write` negado em toda sessão
/// pós-restore) — a marca antiga viria junto e o boot nunca mais perguntaria.
const kLocationAsked = 'location_asked';
const kLocationAskedInstall = 'location_asked_install';

/// Puro/testável: a marca vale pra ESTA instalação?
///
/// [marcadoEm] = hora de instalação gravada com a marca; [instalacao] = a
/// atual (firstInstallTime: não muda em atualização, muda em reinstalação).
/// Sem [marcadoEm] mas com o booleano antigo [legado]: migração de quem já
/// tinha a marca antes desta versão — assume a MESMA instalação, porque
/// perguntar de novo a quem negou de propósito gastaria a segunda negação.
/// Sem [instalacao] (fora do Android) vale a regra antiga.
bool locationAskedThisInstall({int? marcadoEm, int? instalacao, required bool legado}) {
  if (instalacao == null) return legado || marcadoEm != null;
  if (marcadoEm != null) return marcadoEm == instalacao;
  return legado;
}

Future<int?> installTimeMs() async {
  try {
    return (await PackageInfo.fromPlatform()).installTime?.millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }
}

Future<void> markLocationAsked() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kLocationAsked, true);
  final inst = await installTimeMs();
  if (inst != null) await prefs.setInt(kLocationAskedInstall, inst);
}

Future<bool> locationAlreadyAsked() async {
  final prefs = await SharedPreferences.getInstance();
  final inst = await installTimeMs();
  final marcadoEm = prefs.getInt(kLocationAskedInstall);
  final legado = prefs.getBool(kLocationAsked) ?? false;
  // Migração: carimba a instalação atual na marca antiga, senão uma futura
  // reinstalação com restore continuaria sem perguntar.
  if (marcadoEm == null && legado && inst != null) {
    await prefs.setInt(kLocationAskedInstall, inst);
  }
  return locationAskedThisInstall(marcadoEm: marcadoEm, instalacao: inst, legado: legado);
}
