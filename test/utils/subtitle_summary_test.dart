import 'package:PiliPlus/utils/subtitle_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aid = 12;
  const cid = 345;
  const digest = '0123456789abcdef0123456789abcdef';
  const own =
      'https://aisubtitle.hdslb.com/bfs/ai_subtitle/prod/12345$digest?auth_key=1';
  const foreign =
      'https://aisubtitle.hdslb.com/bfs/ai_subtitle/prod/99999$digest';
  const translated =
      'https://aisubtitle.hdslb.com/bfs/ai_subtitle/prod/$digest';
  const cc = 'https://i0.hdslb.com/bfs/subtitle/abc.json';

  test('prod id must match this video', () {
    expect(SubtitleSummary.urlBelongs(own, aid, cid), isTrue);
    expect(
      SubtitleSummary.urlBelongs(
        '//aisubtitle.hdslb.com/bfs/ai_subtitle/prod/12345$digest',
        aid,
        cid,
      ),
      isTrue,
    );
    expect(SubtitleSummary.urlBelongs(foreign, aid, cid), isFalse);
    expect(
      SubtitleSummary.urlBelongs(
        'https://aisubtitle.hdslb.com/bfs/ai_subtitle/prod/99999',
        aid,
        cid,
      ),
      isFalse,
    );
    expect(SubtitleSummary.urlBelongs(translated, aid, cid), isTrue);
    expect(SubtitleSummary.urlBelongs(cc, aid, cid), isTrue);
  });

  test('binary payload still yields subtitle urls', () {
    final raw = 'junk\x00$own\x01https://example.com/not-a-track';
    expect(SubtitleSummary.urlsIn(raw), [own]);
  });

  test('body and conclusion subtitle parts become cues', () {
    final body = SubtitleSummary.cuesFromBody({
      'body': [
        {'from': 1.2, 'to': 2, 'content': '你好'},
        {'from': 2, 'content': '你好'},
        {'from': 3, 'content': '  '},
        {'from': 4, 'content': 'world'},
      ],
    });
    expect(body.map((e) => e.text).toList(), ['你好', 'world']);

    final embedded = SubtitleSummary.cuesFromConclusion({
      'summary': '',
      'subtitle': [
        {
          'part_subtitle': [
            {'start_timestamp': 0, 'content': '第一句'},
            {'start_timestamp': 8, 'content': '第二句'},
          ],
        },
      ],
    });
    expect(embedded.map((e) => e.text).toList(), ['第一句', '第二句']);
  });

  test('any language with text can fill the existing summary', () {
    expect(SubtitleSummary.toResult(const []), isNull);

    final result = SubtitleSummary.toResult(const [
      (from: 0, text: 'opening line about the topic'),
      (from: 30, text: 'middle point that should stay seekable'),
      (from: 70, text: 'closing line'),
    ]);
    expect(result, isNotNull);
    expect(result!.summary, contains('opening line'));
    expect(result.summary, contains('closing line'));
    expect(result.outline, isNotEmpty);
    expect(result.outline!.first.partOutline!.first.timestamp, 0);
    expect(
      result.outline!.last.partOutline!.last.content,
      'closing line',
    );
  });
}