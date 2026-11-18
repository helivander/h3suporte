import 'package:flutter/widgets.dart';

/// Marca a árvore da tela inicial H3: abas, lista vazia e afins usam o visual verde-água.
class H3Estilo extends InheritedWidget {
  const H3Estilo({Key? key, required Widget child})
      : super(key: key, child: child);

  static bool ativo(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<H3Estilo>() != null;

  @override
  bool updateShouldNotify(H3Estilo old) => false;
}
