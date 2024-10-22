import 'package:dev_build/build_support.dart';
import 'package:dev_build/shell.dart';
import 'package:process_run/stdio.dart';
import 'package:tekartik_app_crypto/encrypt.dart';
import 'package:tekartik_app_crypto/password_generator.dart';

ShellEnvironment get _shellEnvironment => ShellEnvironment()
  ..aliases['dsvar'] = 'dart pub global run process_run:shell env --user var';

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

/// Get an environment variable, either regular or encrypted
Future<String> dsUserEnvGetVar(String name) async {
  var value = ShellEnvironment().vars[name];
  if (value == null) {
    try {
      return await dsUserEnvGetEncryptedVar(name);
    } catch (_) {
      throw StateError('Environment var $name not defined');
    }
  } else {
    return value;
  }
}

/// Get an encrypted environment variable
Future<String> dsUserEnvGetEncryptedVar(String name) async {
  var encryptedVarName = _encryptedVarName(name);
  var passwordVarName = _passwordVarName(name);
  var encrypted = ShellEnvironment().vars[encryptedVarName];
  var password = ShellEnvironment().vars[passwordVarName];
  if (encrypted == null || password == null) {
    throw StateError('Encrypted environment var $name not defined');
  }
  return aesDecrypt(encrypted, password);
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
  var password = generatePassword();
  var shell = Shell(environment: _shellEnvironment);
  var encryptedVarName = _encryptedVarName(name);
  var passwordVarName = _passwordVarName(name);
  if (value == null) {
    await shell.run('''
        dsvar delete $encryptedVarName
        dsvar delete $passwordVarName $password
        ''');
  } else {
    var encrypted = aesEncrypt(value, password);
    await shell.run('''
        dsvar set $encryptedVarName $encrypted
        dsvar set $passwordVarName $password
        ''');
  }
  // Force reload
  shellEnvironment = null;
}
