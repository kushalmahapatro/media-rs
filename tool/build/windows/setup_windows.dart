import 'dart:io';

import 'package:logging/logging.dart';

import '../utils/required_directories.dart';

void setupWindows(Map<String, String> envVars, Map<String, String> systemEnv, Logger logger) {
  final msys2Root = getEnv(systemEnv, 'MSYS2_ROOT') ?? r'C:\msys64';
  final mingwBin = '$msys2Root\\mingw64\\bin';
  final currentPath = getEnv(systemEnv, 'PATH') ?? '';

  envVars['PKG_CONFIG'] = 'pkg-config';
  envVars['PKG_CONFIG_ALLOW_SYSTEM_LIBS'] = '1';
  envVars['MSYS2_ROOT'] = msys2Root;
  envVars['PATH'] = '$mingwBin;$currentPath';
  envVars['VCPKG_ROOT'] = r'C:\nonexistent_vcpkg_path';

  // Find LLVM/Clang
  final vsInstallDir = getEnv(systemEnv, 'VSINSTALLDIR');
  final possibleClangPaths = <String>[
    if (getEnv(systemEnv, 'LIBCLANG_PATH') != null) getEnv(systemEnv, 'LIBCLANG_PATH')!,
    r'C:\Program Files\LLVM\bin',
    r'C:\Program Files (x86)\LLVM\bin',
    r'C:\msys64\mingw64\bin',
    if (vsInstallDir != null) '$vsInstallDir\\VC\\Tools\\Llvm\\x64\\bin',
  ].where((p) => Directory(p).existsSync()).toList();

  String? clangPath;
  for (final p in possibleClangPaths) {
    if (File('$p\\clang.dll').existsSync() || File('$p\\libclang.dll').existsSync()) {
      clangPath = p;
      break;
    }
  }

  if (clangPath != null) {
    envVars['LIBCLANG_PATH'] = clangPath;
    envVars['PATH'] = '$clangPath;$mingwBin;$currentPath';
    logger.info('Windows: Found LLVM/Clang at $clangPath');
  } else {
    // final installScript = File(input.packageRoot.resolve('../scripts/support/install_llvm_windows.bat').toFilePath());
    // if (installScript.existsSync()) {
    //   logger.info('Windows: LLVM/Clang not found. Run: ${installScript.path}');
    // }
    logger.warning('Windows: LLVM/Clang not found. bindgen will fail.');
  }
}
