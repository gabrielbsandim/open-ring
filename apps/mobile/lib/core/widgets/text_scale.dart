import 'package:flutter/widgets.dart';

const singleColumnTextScale = 1.3;

extension TextScaleLayout on BuildContext {
  bool get prefersSingleColumn =>
      MediaQuery.textScalerOf(this).scale(1) > singleColumnTextScale;
}
