import 'package:flutter/material.dart';

/// What kind of service something is, read from its name and category - so
/// every option on the menu carries a picture of what it is, as on a shop's
/// shelf, without the salon uploading one per service.
///
/// The words are the ones salons actually write, in English and Hindi
/// (Devanagari and Latin). Anything unrecognised is [ServiceKind.other], which
/// gets the general spa mark - a wrong guess would be worse than a neutral one.
enum ServiceKind { beard, colour, nails, spa, facial, makeup, wax, styling, hair, other }

ServiceKind serviceKind(String name, {String? category}) {
  final s = '${category ?? ''} $name'.toLowerCase();
  bool has(List<String> words) => words.any(s.contains);

  if (has(['beard', 'shave', 'दाढ़ी', 'दाढी', 'shaving', 'moustache', 'daadhi', 'dadhi'])) {
    return ServiceKind.beard;
  }
  if (has(['colour', 'color', 'highlight', 'dye', 'henna', 'mehndi', 'रंग', 'मेहंदी', 'balayage'])) {
    return ServiceKind.colour;
  }
  if (has(['nail', 'manicure', 'pedicure', 'नाखून', 'मैनीक्योर', 'पेडीक्योर'])) {
    return ServiceKind.nails;
  }
  if (has(['massage', 'spa', 'मालिश', 'मसाज', 'champi', 'चंपी', 'malish'])) {
    return ServiceKind.spa;
  }
  if (has(['facial', 'cleanup', 'clean-up', 'skin', 'bleach', 'detan', 'd-tan', 'फेशियल', 'त्वचा'])) {
    return ServiceKind.facial;
  }
  if (has(['makeup', 'make-up', 'bridal', 'party', 'मेकअप', 'दुल्हन', 'saree', 'draping'])) {
    return ServiceKind.makeup;
  }
  if (has(['wax', 'thread', 'eyebrow', 'brow', 'वैक्स', 'थ्रेड', 'आइब्रो', 'upper lip'])) {
    return ServiceKind.wax;
  }
  if (has(['straight', 'smooth', 'keratin', 'rebond', 'perm', 'curl', 'blow', 'iron'])) {
    return ServiceKind.styling;
  }
  if (has(['hair', 'cut', 'trim', 'बाल', 'कटिंग', 'हेयर', 'baal', 'cutting', 'fringe'])) {
    return ServiceKind.hair;
  }
  return ServiceKind.other;
}

IconData serviceIcon(String name, {String? category}) =>
    kindIcon(serviceKind(name, category: category));

IconData kindIcon(ServiceKind kind) => switch (kind) {
  ServiceKind.beard => Icons.face_6_outlined,
  ServiceKind.colour => Icons.palette_outlined,
  ServiceKind.nails => Icons.back_hand_outlined,
  ServiceKind.spa => Icons.self_improvement,
  ServiceKind.facial => Icons.face_retouching_natural,
  ServiceKind.makeup => Icons.brush_outlined,
  ServiceKind.wax => Icons.auto_fix_high_outlined,
  ServiceKind.styling => Icons.waves,
  ServiceKind.hair => Icons.content_cut,
  ServiceKind.other => Icons.spa_outlined,
};

/// A photograph for the kind, where there is one: salon tools and spaces,
/// never people (DESIGN 10; licences in assets/images/CREDITS.md). Null where
/// none fits - the icon stands in. A salon's own photos would replace these.
String? kindImage(ServiceKind kind) => switch (kind) {
  ServiceKind.hair || ServiceKind.styling => 'assets/images/svc_hair.jpg',
  ServiceKind.beard => 'assets/images/svc_barber.jpg',
  ServiceKind.nails => 'assets/images/svc_nails.jpg',
  ServiceKind.facial => 'assets/images/svc_facial.jpg',
  ServiceKind.spa => 'assets/images/svc_spa.jpg',
  ServiceKind.makeup => 'assets/images/svc_makeup.jpg',
  ServiceKind.colour || ServiceKind.wax || ServiceKind.other => null,
};
