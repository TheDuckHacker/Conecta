import 'package:flutter_test/flutter_test.dart';
import 'package:conecta_lsb/services/sign_ai_agent.dart';

Future<String> compose(List<String> signs) async {
  final agent = SignLanguageAiAgent.instance;
  agent.clear();
  var sentence = '';
  for (final s in signs) {
    final out = await agent.ingestSign(s);
    sentence = out.sentence;
  }
  return sentence;
}

void main() {
  test('frases fluidas en orden', () async {
    expect(await compose(['Hola']), 'Hola.');
    expect(await compose(['Cómo']), '¿Cómo estás?');
    expect(await compose(['Hola', 'Cómo']), 'Hola, ¿cómo estás?');
    expect(
      await compose(['Hola', 'Cómo', 'Yo', 'Bien']),
      'Hola, ¿cómo estás? Yo estoy bien.',
    );
    expect(await compose(['Yo', 'Bien']), 'Yo estoy bien.');
    expect(await compose(['Yo', 'Dolor']), 'Yo tengo dolor.');
    expect(await compose(['Gracias']), 'Gracias.');
    expect(
      await compose(['Hola', 'Yo', 'Comer']),
      'Hola, yo quiero comer.',
    );
  });
}
