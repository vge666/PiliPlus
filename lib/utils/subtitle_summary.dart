import 'package:PiliPlus/models_new/video/video_ai_conclusion/model_result.dart';
import 'package:PiliPlus/models_new/video/video_ai_conclusion/outline.dart';
import 'package:PiliPlus/models_new/video/video_ai_conclusion/part_outline.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';

typedef SubtitleCue = ({double from, String text});

/// 把字幕正文收成现有的 [AiConclusionResult]。
abstract final class SubtitleSummary {
  static final _prodId = RegExp(r'^(\d*)([0-9a-fA-F]{32})');
  static final _urlRe = RegExp(
    r'(?:https?:)?//[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+',
  );

  /// AI subtitle objects embed `aid+cid` before the digest. A different id
  /// belongs to another part or another video and is not usable.
  static bool urlBelongs(String url, int aid, int cid) {
    final uri = Uri.tryParse(url.http2https);
    if (uri == null || uri.host.isEmpty) return false;
    final prod = uri.path.indexOf('/prod/');
    if (prod < 0) return true;
    final rest = uri.path.substring(prod + '/prod/'.length);
    final match = _prodId.firstMatch(rest);
    final prefix = match?.group(1);
    if (prefix == null) {
      final digits = RegExp(r'^(\d+)').firstMatch(rest)?.group(1);
      return digits == null || digits == '$aid$cid';
    }
    if (prefix.isEmpty) return true;
    return prefix == '$aid$cid';
  }

  static List<String> urlsIn(String raw) {
    final urls = <String>[];
    for (final match in _urlRe.allMatches(raw)) {
      var url = match.group(0)!;
      while (url.endsWith('.') || url.endsWith(',')) {
        url = url.substring(0, url.length - 1);
      }
      if (!url.toLowerCase().contains('subtitle')) continue;
      if (urls.contains(url)) continue;
      urls.add(url);
    }
    return urls;
  }

  static List<SubtitleCue> cuesFromBody(Object? data) {
    final body = switch (data) {
      {'body': final List list} => list,
      {'data': {'body': final List list}} => list,
      final List list => list,
      _ => null,
    };
    if (body == null) return const [];
    return _cues(body, fromKey: 'from', altKey: 'start_timestamp');
  }

  static List<SubtitleCue> cuesFromConclusion(Object? modelResult) {
    if (modelResult is! Map) return const [];
    final subtitle = modelResult['subtitle'];
    if (subtitle is! List) return const [];
    final cues = <SubtitleCue>[];
    for (final part in subtitle) {
      if (part is! Map) continue;
      final lines = part['part_subtitle'];
      if (lines is! List) continue;
      cues.addAll(_cues(lines, fromKey: 'start_timestamp', altKey: 'from'));
    }
    return cues;
  }

  static List<SubtitleCue> _cues(
    List body, {
    required String fromKey,
    required String altKey,
  }) {
    final cues = <SubtitleCue>[];
    for (final item in body) {
      if (item is! Map) continue;
      final text = item['content']?.toString().trim();
      if (text == null || text.isEmpty) continue;
      final from = switch (item[fromKey] ?? item[altKey]) {
        final num n => n.toDouble(),
        final String s => double.tryParse(s) ?? 0,
        _ => 0.0,
      };
      if (cues.isNotEmpty && cues.last.text == text) continue;
      cues.add((from: from, text: text));
    }
    return cues;
  }

  static AiConclusionResult? toResult(List<SubtitleCue> cues) {
    if (cues.isEmpty) return null;
    final sorted = [...cues]..sort((a, b) => a.from.compareTo(b.from));
    final lines = <SubtitleCue>[];
    for (final cue in sorted) {
      final text = cue.text.trim();
      if (text.isEmpty) continue;
      if (lines.isNotEmpty && lines.last.text == text) continue;
      lines.add((from: cue.from, text: text));
    }
    if (lines.isEmpty) return null;
    final span = lines.last.from - lines.first.from;
    final bucket = span <= 20
        ? double.infinity
        : (span / 8).clamp(20, 180).toDouble();
    final groups = <List<SubtitleCue>>[];
    var current = <SubtitleCue>[];
    for (final line in lines) {
      if (current.isNotEmpty && line.from - current.first.from >= bucket) {
        groups.add(current);
        current = <SubtitleCue>[];
      }
      current.add(line);
    }
    if (current.isNotEmpty) groups.add(current);

    final outline = <Outline>[];
    final leads = <String>[];
    for (final group in groups) {
      final first = group.first;
      leads.add(first.text);
      final parts = <PartOutline>[
        PartOutline(timestamp: first.from.floor(), content: first.text),
      ];
      if (group.length > 2) {
        final mid = group[group.length ~/ 2];
        if (mid.text != first.text) {
          parts.add(PartOutline(timestamp: mid.from.floor(), content: mid.text));
        }
      }
      if (group.length > 1) {
        final last = group.last;
        if (last.text != parts.last.content) {
          parts.add(PartOutline(timestamp: last.from.floor(), content: last.text));
        }
      }
      outline.add(Outline(title: _clip(first.text, 36), partOutline: parts));
    }

    final summary = _clip(
      groups.length == 1
          ? lines.map((e) => e.text).join(' ')
          : leads.join('；'),
      360,
    );
    if (summary.isEmpty && outline.isEmpty) return null;
    return AiConclusionResult(
      summary: summary.isEmpty ? null : summary,
      outline: outline.isEmpty ? null : outline,
    );
  }

  static bool hasText(AiConclusionResult? result) =>
      result?.summary?.isNotEmpty == true || result?.outline?.isNotEmpty == true;

  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }
}
