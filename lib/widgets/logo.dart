import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CovesLogo extends StatelessWidget {
  final double size;
  final bool useColorVersion;

  const CovesLogo({super.key, this.size = 150, this.useColorVersion = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(bottom: 16),
      child: SvgPicture.asset(
        useColorVersion
            ? 'assets/logo/coves-shark-color.svg'
            : 'assets/logo/coves-shark.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
