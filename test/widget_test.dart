import 'package:flutter_test/flutter_test.dart';
import 'package:conecta_lsb/main.dart';

void main() {
  testWidgets('App inicia correctamente', (WidgetTester tester) async {
    await tester.pumpWidget(const ConectaApp());
    await tester.pumpAndSettle();

    // Verificar que el título "Conecta" aparece en pantalla
    expect(find.text('Conecta'), findsWidgets);
  });
}
