import 'dart:io';

import 'package:dev_build/menu/menu_io.dart';
import 'package:dev_build/shell.dart' hide prompt;
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_prj_tktools/dsenv.dart';
import 'package:tekartik_prj_tktools/src/dtk/dtk_prj_menu.dart';

import 'dtk_dep_menu.dart';
import 'dtk_git_menu.dart';
import 'dtk_pub_menu.dart';

Future<void> main(List<String> args) async {
  mainMenuConsole(args, dtkMenu);
}

/// dtk menu
void dtkMenu({String? path}) {
  _dtkMenu(path: path ?? '.');
}

/// dtk menu
void _dtkMenu({required String path}) {
  enter(() async {});
  menu('git', () {
    dtkGitMenu();
  });
  menu('dep', () {
    dtkDepMenu();
  });
  menu('prj', () {
    dtkPrjMenu(path: path);
  });
  menu('pub', () {
    dtkPubMenu();
  });
  menu('env', () {
    item('prompt DTK_HOSTNAME', () async {
      var platformHostname = Platform.localHostname;
      writeln('localHostname: $platformHostname');
      var dsEnvNostname = shellEnvironment['DTK_HOSTNAME'];
      writeln("shellEnvironment['DTK_HOSTNAME']: $dsEnvNostname");

      var hostname = await prompt(
        'New hostname (${dsEnvNostname ?? platformHostname})',
      );
      if (hostname.isNotEmpty && hostname != dsEnvNostname) {
        await dsUserEnvSetVar('DTK_HOSTNAME', hostname);
        writeln('DTK_HOSTNAME set to $hostname');
      } else {
        writeln('No change');
      }
    });
    item('clear DTK_HOSTNAME', () async {
      var dsEnvNostname = shellEnvironment['DTK_HOSTNAME'];
      if (dsEnvNostname != null) {
        await dsUserEnvSetVar('DTK_HOSTNAME', null);
        writeln('DTK_HOSTNAME cleared');
      } else {
        writeln('DTK_HOSTNAME not set');
      }
    });
  });
}
