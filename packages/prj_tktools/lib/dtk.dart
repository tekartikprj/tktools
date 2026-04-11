/// Tools for Dart handling multiple projects
library;

export 'src/dtk/dtk.dart'
    show
        dtkGitExportPathGlobalPrefsKey,
        dtkDepExportPathGlobalPrefsKey,
        dtkHostEnvExportPathGlobalPrefsKey,
        dtkGetGitExportPath,
        dtkGitUniqueNameFromUrl;
export 'src/dtk/dtk_config_db.dart' show DtkConfigDb, dtkConfigDbAction;
export 'src/dtk/dtk_git_config_db.dart'
    show
        dtkGitGetAllRepositories,
        dtkGitConfigDbAction,
        DbDtkGitRepository,
        DbDtkGitRepositoryExt,
        DtkGitConfigDb,
        DtkGitConfigDbExt;
export 'src/dtk/dtk_host_env_config_db.dart'
    show dtkHostEnvVarGet, dtkHostEnvVarSet;
export 'src/dtk/dtk_menu.dart' show dtkMenu;
