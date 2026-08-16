/// Dtk dependency config (minimum version of the shared dependencies)
library;

export 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

export 'package:tekartik_prj_tktools/src/dtk/dtk.dart'
    show dtkDepExportPathGlobalPrefsKey, dtkGetDepExportPath;
export 'package:tekartik_prj_tktools/src/dtk/dtk_dep_config_db.dart'
    show
        DbDtkDepDependency,
        DtkDepConfigDb,
        dtkDepConfigDbAction,
        DtkDepConfigDbExt,
        dtkDepGetAllDependencies;
