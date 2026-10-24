import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/fluxidi_play_distribution.dart';

void main() {
  for (final language in ['nl', 'en', 'fr', 'es']) {
    for (final width in [240.0, 540.0, 1100.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$language notice fits $width px at text scale $scale', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(const Size(1200, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          const noticeKey = ValueKey('notice');
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FluxidiPlaySaasManagedOutsideNotice(
                              key: noticeKey,
                              languageCode: language,
                              backgroundColor: Colors.black,
                              borderColor: Colors.amber,
                              textColor: Colors.white,
                            ),
                            const Text('Following content'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final message = fluxidiPlaySaasManagedOutsideMessage(
            languageCode: language,
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(message),
          );
          final noticeRect = tester.getRect(find.byKey(noticeKey));
          final paragraphRect = tester.getRect(find.text(message));
          // Flutter selection boxes can extend past a wrap point for trailing
          // whitespace. Check the visible words, including the final word.
          final boxes = [
            for (final word in RegExp(r'\S+').allMatches(message))
              ...paragraph.getBoxesForSelection(
                TextSelection(baseOffset: word.start, extentOffset: word.end),
              ),
          ];

          expect(tester.takeException(), isNull);
          expect(noticeRect.width, width);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(boxes, isNotEmpty);
          if (width == 240) {
            expect(boxes.last.top, greaterThan(boxes.first.top));
          }
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(-0.01));
            expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
            expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
          }
          expect(paragraphRect.left, greaterThanOrEqualTo(noticeRect.left));
          expect(paragraphRect.right, lessThanOrEqualTo(noticeRect.right));
          expect(paragraphRect.bottom, lessThanOrEqualTo(noticeRect.bottom));
          expect(
            tester.getRect(find.text('Following content')).top,
            greaterThanOrEqualTo(noticeRect.bottom),
          );
          expect(find.byType(GestureDetector), findsNothing);
          expect(find.byType(TextButton), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
        });
      }
    }
  }
}
