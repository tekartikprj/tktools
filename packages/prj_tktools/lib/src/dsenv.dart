import 'package:dev_build/build_support.dart';
import 'package:dev_build/shell.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_crypto/encrypt.dart';
import 'package:tekartik_app_crypto/password_generator.dart';
export 'package:tekartik_prj_tktools/src/dsenv/key_value_io.dart';

ShellEnvironment get _shellEnvironment => ShellEnvironment()
  ..aliases['dsvar'] =
      'dart run --verbosity error process_run:shell env --user var';

var _processRunGlobalReady = () async {
  await checkAndActivatePackage('process_run');
}();
var _testEnVar = 'TEST_ENV_VAR';
Future<void> main() async {
  await dsUserEnvSetVar(_testEnVar, null);
  await dsUserEnvSetEncryptedVar(_testEnVar, 'some value');

  stdout.writeln('$_testEnVar: ${await dsUserEnvGetVar(_testEnVar)}');
}

String _encryptedVarName(String name) {
  return '${name}_ENC';
}

String _passwordVarName(String name) {
  return '${name}_ENC_PWD';
}

/// Get an environment variable, either regular or encrypted, throw if not found
Future<String> dsUserEnvGetVar(String name) async {
  return dsUserEnvGetVarSync(name);
}

/// Get an environment variable, either regular or encrypted, throw if not found
String dsUserEnvGetVarSync(String name) {
  var value = dsUserEnvGetVarOrNullSync(name);
  if (value == null) {
    throw StateError('Environment var $name not defined');
  }
  return value;
}

/// Get an environment variable, either regular or encrypted
Future<String?> dsUserEnvGetVarOrNull(String name) async {
  return dsUserEnvGetVarOrNullSync(name);
}

/// Get an environment variable, either regular or encrypted
String? dsUserEnvGetVarOrNullSync(String name) {
  var value = ShellEnvironment().vars[name];
  if (value == null) {
    return dsUserEnvGetEncryptedVarOrNullSync(name);
  } else {
    return value;
  }
}

/// Get an encrypted environment variable, throw if not found
Future<String> dsUserEnvGetEncryptedVar(String name) async {
  return dsUserEnvGetEncryptedVarSync(name);
}

/// Get an encrypted environment variable, throw if not found
String dsUserEnvGetEncryptedVarSync(String name) {
  var value = dsUserEnvGetEncryptedVarOrNullSync(name);
  if (value == null) {
    throw StateError('Encrypted environment var $name not defined');
  }
  return value;
}

/// Get an encrypted environment variable
Future<String?> dsUserEnvGetEncryptedVarOrNull(String name) async {
  return dsUserEnvGetEncryptedVarOrNullSync(name);
}

/// Get an encrypted environment variable
String? dsUserEnvGetEncryptedVarOrNullSync(String name) {
  var encryptedVarName = _encryptedVarName(name);
  var passwordVarName = _passwordVarName(name);
  var encrypted = ShellEnvironment().vars[encryptedVarName];
  var password = ShellEnvironment().vars[passwordVarName];
  if (encrypted == null || password == null) {
    return null;
  }
  try {
    return aesDecrypt(encrypted, password);
  } catch (_) {
    return null;
  }
}

/// Clear both normal and encrypted environment variable
Future<void> dsUserClearVar(String name) async {
  await dsUserEnvSetVar(name, null);
  await dsUserEnvSetEncryptedVar(name, null);
}

/// Set an environment variable
Future<void> dsUserEnvSetVar(String name, String? value) async {
  await _processRunGlobalReady;
  var shell = Shell(environment: _shellEnvironment);
  if (value == null) {
    await shell.run('''
        dsvar delete $name
        ''');
  } else {
    await shell.run('''
        dsvar set $name $value
        ''');
  }
  // Force reload
  shellEnvironment = null;
}

/// Set an environment variable
Future<void> dsUserEnvSetEncryptedVar(String name, String? value) async {
  await _processRunGlobalReady;

  var shell = Shell(environment: _shellEnvironment);
  var encryptedVarName = _encryptedVarName(name);
  var passwordVarName = _passwordVarName(name);
  if (value == null) {
    await shell.run('''
        dsvar delete $encryptedVarName
        dsvar delete $passwordVarName
        ''');
  } else {
    var password = generatePassword();
    var encrypted = aesEncrypt(value, password);
    await shell.run('''
        dsvar set $encryptedVarName $encrypted
        dsvar set $passwordVarName $password
        ''');
  }
  // Force reload
  shellEnvironment = null;
}
