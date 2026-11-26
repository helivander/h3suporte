import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('H3Raios', () {
    test('define escala geométrica crescente padrão', () {
      expect(H3Raios.xs, 6);
      expect(H3Raios.sm, 8);
      expect(H3Raios.md, 12);
      expect(H3Raios.lg, 16);
      expect(H3Raios.full, 999);
      expect(H3Raios.xs < H3Raios.sm, isTrue);
      expect(H3Raios.sm < H3Raios.md, isTrue);
      expect(H3Raios.md < H3Raios.lg, isTrue);
      expect(H3Raios.lg < H3Raios.full, isTrue);
    });
  });

  group('H3Tokens', () {
    test('copyWith altera apenas os campos informados', () {
      const novoDestaque = Color(0xFF123456);
      final modificado = H3Tokens.dark.copyWith(destaque: novoDestaque);

      expect(modificado.destaque, novoDestaque);
      expect(modificado.fundo, H3Tokens.dark.fundo);
      expect(modificado.painel, H3Tokens.dark.painel);
      expect(modificado.texto, H3Tokens.dark.texto);
      expect(modificado.perigo, H3Tokens.dark.perigo);
    });

    test('lerp interpola nos extremos e retorna this quando other é nulo', () {
      final emZero = H3Tokens.dark.lerp(H3Tokens.light, 0.0);
      expect(emZero.fundo, H3Tokens.dark.fundo);
      expect(emZero.destaque, H3Tokens.dark.destaque);

      final emUm = H3Tokens.dark.lerp(H3Tokens.light, 1.0);
      expect(emUm.fundo, H3Tokens.light.fundo);
      expect(emUm.destaque, H3Tokens.light.destaque);

      final meio = H3Tokens.dark.lerp(H3Tokens.light, 0.5);
      expect(meio.fundo, Color.lerp(H3Tokens.dark.fundo, H3Tokens.light.fundo, 0.5));

      final nulo = H3Tokens.dark.lerp(null, 0.5);
      expect(identical(nulo, H3Tokens.dark), isTrue);
    });

    testWidgets('of(context) usa extensão quando presente ou cai para brightness',
        (tester) async {
      late H3Tokens capturado;

      await tester.pumpWidget(
        Theme(
          data: ThemeData.light(),
          child: Builder(builder: (context) {
            capturado = H3Tokens.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(capturado.fundo, H3Tokens.light.fundo);

      await tester.pumpWidget(
        Theme(
          data: ThemeData.dark(),
          child: Builder(builder: (context) {
            capturado = H3Tokens.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(capturado.fundo, H3Tokens.dark.fundo);

      final custom = H3Tokens.light.copyWith(destaque: const Color(0xFFABCDEF));
      await tester.pumpWidget(
        Theme(
          data: ThemeData.light().copyWith(extensions: [custom]),
          child: Builder(builder: (context) {
            capturado = H3Tokens.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(capturado.destaque, const Color(0xFFABCDEF));
    });
  });

  group('H3Estilo', () {
    testWidgets('ativo(context) reflete presença do InheritedWidget',
        (tester) async {
      late bool semEstilo;
      late bool comEstilo;

      await tester.pumpWidget(
        Builder(builder: (context) {
          semEstilo = H3Estilo.ativo(context);
          return H3Estilo(
            child: Builder(builder: (innerContext) {
              comEstilo = H3Estilo.ativo(innerContext);
              return const SizedBox.shrink();
            }),
          );
        }),
      );

      expect(semEstilo, isFalse);
      expect(comEstilo, isTrue);
    });
  });
}
