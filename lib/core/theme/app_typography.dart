import 'package:fluent_ui/fluent_ui.dart';

class AppTypography {
  AppTypography._();

  static Typography fromBrightness({
    required Brightness brightness,
    required String fontFamily,
  }) {
    final base = Typography.fromBrightness(brightness: brightness).apply(
      fontFamily: fontFamily,
    );

    return base.merge(
      Typography.raw(
        display: base.display?.copyWith(
          fontSize: 64,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
        title: base.title?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        subtitle: base.subtitle?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
        bodyStrong: base.bodyStrong?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        body: base.body?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
        caption: base.caption?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
      ),
    );
  }
}
