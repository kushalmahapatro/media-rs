import 'dart:io' show Platform;

bool encoderIgnoresPerBitrateCap() => Platform.isIOS;
