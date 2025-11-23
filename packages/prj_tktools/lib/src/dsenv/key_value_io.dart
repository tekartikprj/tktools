import 'package:tekartik_app_dev_menu/dev_menu.dart';
import 'package:tekartik_prj_tktools/dsenv.dart';
//import 'package:tekartik_test_menu_io/src/vars.dart';

/// io helper
extension KeyValueEncryptedIoExt on KeyValue {
  /// Prompt env and global save
  Future<KeyValue> promptToEnvEncrypted() async {
    var newValue = await prompt('$key${valid ? ' ($value)' : ''}');
    if (newValue.isNotEmpty) {
      await setToEnvEncrypted(newValue);
    }
    return this;
  }

  /// Set to encrypted env var
  Future<void> setToEnvEncrypted(String value) async {
    this.value = value;
    await dsUserEnvSetEncryptedVar(key, value);
  }

  /// Delete from encrypted env var
  Future<void> deleteFromEnvEncrypted() async {
    value = null;
    await dsUserEnvSetEncryptedVar(key, null);
  }
}

/// Util on list
extension KeyValueListEncryptedIoExt on Iterable<KeyValue> {
  /// Prompt env and global save
  Future<void> promptToEnvEncrypted({bool? ifInvalid}) async {
    for (var kv in this) {
      if (ifInvalid ?? false) {
        if (kv.valid) {
          continue;
        }
      }
      await kv.promptToEnvEncrypted();
    }
  }
}

final _exportCache = <String, String?>{};

/// io helper
extension KeyValueKeyEncryptedIoExt on String {
  /// Encrypted env var key value.
  KeyValue kvFromEnvEncrypted({String? defaultValue}) {
    return KeyValue(this, fromEnvEncrypted(defaultValue: defaultValue));
  }

  /// Encrypted env var value.
  String? fromEnvEncrypted({String? defaultValue}) {
    var value = _exportCache[this] ??=
        dsUserEnvGetEncryptedVarOrNullSync(this) ?? defaultValue;
    return value;
  }
}

/// Key values menu.
void keyValuesEncryptedMenu(String name, Iterable<KeyValue> kvs) {
  menu(name, () {
    item('dump', () async {
      write('${kvs.length} key values:');
      for (var kv in kvs) {
        write(kv);
      }
    });
    item('all', () async {
      await kvs.promptToEnvEncrypted();
    });
    item('prompt invalids', () async {
      await kvs.promptToEnvEncrypted(ifInvalid: true);
    });
    void allKv() {
      for (var kv in kvs) {
        item('update ${kv.key}', () async {
          var newKv = await kv.promptToEnvEncrypted();
          write(newKv);
        });
      }
    }

    if (kvs.length < 6) {
      allKv();
    } else {
      menu('one by one', () {
        allKv();
      });
    }
    item('clear one by one', () {
      for (var kv in kvs) {
        item('delete ${kv.key}', () async {
          await kv.deleteFromEnvEncrypted();
          write(kv);
        });
      }
    });
  });
}
