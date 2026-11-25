import 'package:flutter/material.dart';

/// Marca a árvore da tela inicial H3: abas, lista vazia e afins usam o visual verde-água.
class H3Estilo extends InheritedWidget {
  const H3Estilo({Key? key, required Widget child})
      : super(key: key, child: child);

  static bool ativo(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<H3Estilo>() != null;

  @override
  bool updateShouldNotify(H3Estilo old) => false;
}

/// Escala geométrica padrão do H3 Suporte.
class H3Raios {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double full = 999;
}

/// Tokens imutáveis de cor do tema H3 Suporte.
class H3Tokens extends ThemeExtension<H3Tokens> {
  final Color fundo;
  final Color painel;
  final Color painel2;
  final Color linha;
  final Color linha2;
  final Color texto;
  final Color apagado;
  final Color destaque;
  final Color destaqueTinta;
  final Color ok;
  final Color aviso;
  final Color info;
  final Color perigo;
  final Color perigoTinta;

  const H3Tokens({
    required this.fundo,
    required this.painel,
    required this.painel2,
    required this.linha,
    required this.linha2,
    required this.texto,
    required this.apagado,
    required this.destaque,
    required this.destaqueTinta,
    required this.ok,
    required this.aviso,
    required this.info,
    required this.perigo,
    required this.perigoTinta,
  });

  static const dark = H3Tokens(
    fundo: Color(0xFF070D10),
    painel: Color(0xFF0E171B),
    painel2: Color(0xFF132026),
    linha: Color(0xFF1D2D33),
    linha2: Color(0xFF26393F),
    texto: Color(0xFFE6F1F2),
    apagado: Color(0xFF8AA1A6),
    destaque: Color(0xFF1FD1C1),
    destaqueTinta: Color(0xFF04201D),
    ok: Color(0xFF3DDC84),
    aviso: Color(0xFFF0B544),
    info: Color(0xFF4F8CFF),
    perigo: Color(0xFFFF5D6C),
    perigoTinta: Color(0xFFFFFFFF),
  );

  static const light = H3Tokens(
    fundo: Color(0xFFE9EFF1),
    painel: Color(0xFFFFFFFF),
    painel2: Color(0xFFF4F8F9),
    linha: Color(0xFFDCE5E8),
    linha2: Color(0xFFC9D6DA),
    texto: Color(0xFF13262B),
    apagado: Color(0xFF587177),
    destaque: Color(0xFF087F76),
    destaqueTinta: Color(0xFFFFFFFF),
    ok: Color(0xFF1C9A58),
    aviso: Color(0xFFB5730F),
    info: Color(0xFF2D6BDB),
    perigo: Color(0xFFC6283A),
    perigoTinta: Color(0xFFFFFFFF),
  );

  static H3Tokens of(BuildContext context) {
    final ext = Theme.of(context).extension<H3Tokens>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  @override
  H3Tokens copyWith({
    Color? fundo,
    Color? painel,
    Color? painel2,
    Color? linha,
    Color? linha2,
    Color? texto,
    Color? apagado,
    Color? destaque,
    Color? destaqueTinta,
    Color? ok,
    Color? aviso,
    Color? info,
    Color? perigo,
    Color? perigoTinta,
  }) =>
      H3Tokens(
        fundo: fundo ?? this.fundo,
        painel: painel ?? this.painel,
        painel2: painel2 ?? this.painel2,
        linha: linha ?? this.linha,
        linha2: linha2 ?? this.linha2,
        texto: texto ?? this.texto,
        apagado: apagado ?? this.apagado,
        destaque: destaque ?? this.destaque,
        destaqueTinta: destaqueTinta ?? this.destaqueTinta,
        ok: ok ?? this.ok,
        aviso: aviso ?? this.aviso,
        info: info ?? this.info,
        perigo: perigo ?? this.perigo,
        perigoTinta: perigoTinta ?? this.perigoTinta,
      );

  @override
  H3Tokens lerp(ThemeExtension<H3Tokens>? other, double t) {
    if (other is! H3Tokens) return this;
    return H3Tokens(
      fundo: Color.lerp(fundo, other.fundo, t) ?? fundo,
      painel: Color.lerp(painel, other.painel, t) ?? painel,
      painel2: Color.lerp(painel2, other.painel2, t) ?? painel2,
      linha: Color.lerp(linha, other.linha, t) ?? linha,
      linha2: Color.lerp(linha2, other.linha2, t) ?? linha2,
      texto: Color.lerp(texto, other.texto, t) ?? texto,
      apagado: Color.lerp(apagado, other.apagado, t) ?? apagado,
      destaque: Color.lerp(destaque, other.destaque, t) ?? destaque,
      destaqueTinta:
          Color.lerp(destaqueTinta, other.destaqueTinta, t) ?? destaqueTinta,
      ok: Color.lerp(ok, other.ok, t) ?? ok,
      aviso: Color.lerp(aviso, other.aviso, t) ?? aviso,
      info: Color.lerp(info, other.info, t) ?? info,
      perigo: Color.lerp(perigo, other.perigo, t) ?? perigo,
      perigoTinta: Color.lerp(perigoTinta, other.perigoTinta, t) ?? perigoTinta,
    );
  }
}
