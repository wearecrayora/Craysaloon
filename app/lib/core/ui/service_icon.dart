import 'package:flutter/material.dart';

/// An icon for a service, read from its name and category - so every option
/// on the menu carries a picture of what it is, as on a shop's shelf, without
/// the salon uploading one per service.
///
/// The words are the ones salons actually write, in English and Hindi
/// (Devanagari and Latin). Anything unrecognised gets the general spa mark;
/// a wrong guess would be worse than a neutral one.
IconData serviceIcon(String name, {String? category}) {
  final s = '${category ?? ''} $name'.toLowerCase();
  bool has(List<String> words) => words.any(s.contains);

  if (has(['beard', 'shave', 'दाढ़ी', 'दाढी', 'shaving', 'moustache', 'daadhi', 'dadhi'])) {
    return Icons.face_6_outlined;
  }
  if (has(['colour', 'color', 'highlight', 'dye', 'henna', 'mehndi', 'रंग', 'मेहंदी', 'balayage'])) {
    return Icons.palette_outlined;
  }
  if (has(['nail', 'manicure', 'pedicure', 'नाखून', 'मैनीक्योर', 'पेडीक्योर'])) {
    return Icons.back_hand_outlined;
  }
  if (has(['massage', 'spa', 'मालिश', 'मसाज', 'champi', 'चंपी', 'malish'])) {
    return Icons.self_improvement;
  }
  if (has(['facial', 'cleanup', 'clean-up', 'skin', 'bleach', 'detan', 'd-tan', 'फेशियल', 'त्वचा'])) {
    return Icons.face_retouching_natural;
  }
  if (has(['makeup', 'make-up', 'bridal', 'party', 'मेकअप', 'दुल्हन', 'saree', 'draping'])) {
    return Icons.brush_outlined;
  }
  if (has(['wax', 'thread', 'eyebrow', 'brow', 'वैक्स', 'थ्रेड', 'आइब्रो', 'upper lip'])) {
    return Icons.auto_fix_high_outlined;
  }
  if (has(['straight', 'smooth', 'keratin', 'rebond', 'perm', 'curl', 'blow', 'iron'])) {
    return Icons.waves;
  }
  if (has(['hair', 'cut', 'trim', 'बाल', 'कटिंग', 'हेयर', 'baal', 'cutting', 'fringe'])) {
    return Icons.content_cut;
  }
  return Icons.spa_outlined;
}
