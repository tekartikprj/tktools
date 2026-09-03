# Local workspace

A local workspace is a folder holding a `local_workspace.json` file which lists
the projects (folders) to aggregate in a single IDE/agent workspace.

The file is described by `DtkLocalWorkspace` (`package:tekartik_prj_tktools/local_workspace.dart`)
and handled by `LocalWorkspaceHelper` and the `local_workspace` command line tool.

## `local_workspace.json` format

```json
{
  "links": ["../../some_repo", "../../another_repo"],
  "add-git": ["tekartik_common_utils", "tekartik/dev_test.dart"],
  "add": ["some_package"],
  "add-dir": ["../../some_folder", "/absolute/path/to/some_folder"]
}
```

All fields are optional.

| Field     | Model field | Content                | Symlink created                    |
|-----------|-------------|------------------------|------------------------------------|
| `links`   | `links`     | relative paths         | `./projects/<basename>`            |
| `add-git` | `addGit`    | package name, git url or github relative path | `./projects/<org>/<repo>` |
| `add`     | `add`       | package name           | `./projects/<org>/<repo>/<gitPath>` |
| `add-dir` | `addDir`    | relative or absolute paths | none                           |

### `links`

List of paths relative to the workspace. For each entry, a symlink is created at
`./projects/<basename>` pointing to the absolute target. No tkpub lookup is
needed.

The target must exist, resolution fails otherwise.

### `add-git`

List of packages to symlink at repo level, keeping the github tree. The package
is looked up in the tkpub config (`tkpub` db) to find its git url, unless the
entry is already a git url (`https://...`, `git@...`) or a github relative path
(`tekartik/dev_test.dart`).

`tekartik_lints` (git url `tekartik/common.dart`) creates
`./projects/tekartik/common.dart` -> local clone of the whole repo.

### `add`

Same as `add-git` but the symlink points to the package path within its git
repo. `tekartik_lints` (git url `tekartik/common.dart`, git path
`packages/lints`) creates `./projects/tekartik/common.dart/packages/lints` ->
local package path.

### `add-dir`

List of existing folders, either relative to the workspace or absolute:

```json
{
  "add-dir": [
    "../../some_folder",
    "/home/user/git/gitlab.com/some_org/some_project"
  ]
}
```

No symlink is created and no tkpub lookup is done: the folder is added to the
workspace as is. This is the way to add a project living outside the github tree
(other git host, other local root...).

A missing folder is skipped with a warning on stderr (an absolute path typically
only exists on a given machine).

## Resolution

The config is resolved to a list of folders relative to the workspace, in this
order: `links`, `add-dir`, `add-git`, `add`. The workspace itself (`.`) is always
the first folder.

The result is cached in:

- `.local/local_workspace/resolved.json`: `DtkResolvedLocalWorkspace`, the input
  config, the resolved entries (`type`, `source`, `path`) and the format
  `version` (`dtkResolvedLocalWorkspaceVersion`).
- `.local/local_workspace/resolved_input.json`: the input config only, used to
  check whether `local_workspace.json` changed since the last resolution.

Unknown fields in `local_workspace.json` are ignored (and not kept in the
resolved input, so they make the cache check always report a change).

## Command line

From `package:tekartik_prj_tools` (`bin/local_workspace.dart`):

```shell
# Create the symlinks declared by links/add-git/add (add-dir has none)
local_workspace setup-symlinks

# All setup operations: vscode, idea, claude, agy
local_workspace setup

# Individual setup operations
local_workspace setup-vscode  # <dir_name>.code-workspace
local_workspace setup-idea    # .idea/modules.xml and .idea/<dir_name>.iml
local_workspace setup-claude  # .claude/settings.json permissions.additionalDirectories
local_workspace setup-agy     # .gemini/antigravity-cli/settings.json permissions.allow

# Resolution
local_workspace resolve          # write .local/local_workspace/*.json
local_workspace resolve --dump   # display the resolved paths
local_workspace resolve --check  # fail if the input changed

# Add a package to projects/ (symlink only, does not modify the json)
local_workspace add <package1> [package2...]
local_workspace add-git <package1> [package2...]
```

All commands accept `--dir <path>` (default `.`) to specify the workspace
folder.

## API

```dart
import 'package:tekartik_prj_tktools/local_workspace.dart';

var helper = LocalWorkspaceHelper(path: '.');
var config = await helper.loadConfig();

// Folders relative to the workspace, '.' included
var folders = await helper.resolveFolders(config);

// Absolute canonical folders, '.' included
var topFolders = await helper.getTopFolders();
```
