# Project Notes

## Local dev setup: sample app + tracker together

`surfside-ios-sample-app` depends on `../surfside-ios-tracker` (sibling repo)
via `XCLocalSwiftPackageReference` in `SurfsideApp.xcodeproj/project.pbxproj`
(`relativePath = "../surfside-ios-tracker"`). No symlink needed — SPM resolves
the relative path directly.

Opening both repos as separate Xcode projects/workspaces at the same time
causes: `Couldn't load surfside-ios-tracker because it is already opened from
another project or workspace` + `Missing package product 'SurfsideTracker'`.
Xcode locks a local SPM package to one open context.

Fix: created a combined workspace at
`/Users/jamesspillmann/Desktop/dev/gitlab/Surfside.xcworkspace` (one level up,
outside both repos, so it's untracked by either repo's git — kept deliberately
out of both, since the two projects are separate repos in GitLab and should
stay that way in the commit history). It references both
`surfside-ios-sample-app/SurfsideApp.xcodeproj` and `surfside-ios-tracker` as
sibling `FileRef`s. Open this workspace instead of either project individually
when working on both at once.

## Deployment target pinned to 18.2 (was 18.4)

Local Xcode is 16.2, which only ships iOS 18.2 SDK (iOS 18.4 SDK requires
Xcode 16.3+, and this machine is capped at 16.2 by macOS version). Project
originally had `IPHONEOS_DEPLOYMENT_TARGET = 18.4` in all 4 build configs in
`project.pbxproj`, which made every simulator (including all iPads) fail to
show as selectable in the destination picker. Lowered all 4 to `18.2` to
match. If the team later moves to Xcode 16.3+, this can go back to 18.4.

## Scheme was broken — Run silently did nothing

`SurfsideApp.xcodeproj/xcshareddata/xcschemes/SurfsideSampleApp.xcscheme` had
a `<LaunchAction>` with no `<BuildableProductRunnable>` — meaning Run had no
executable to hand off to after building. Symptom: "Build Succeeded" shows in
the toolbar, no error, but nothing launches (no simulator boots, no process
starts). Fixed by adding the missing `BuildableProductRunnable` block pointing
at `SurfsideApp.app` (blueprint id `0209B7E52E20ED310037171C`).

Note: after editing a `.xcscheme` file on disk, switching schemes away and
back in Xcode's UI does NOT reliably reload it — Xcode can keep the old
version cached in memory. A full quit and relaunch is needed to pick up
external edits to scheme files.

**Still outstanding**: the same scheme's `TestAction` references container
`SurfsideSampleApp.xcodeproj`, but the actual project file is
`SurfsideApp.xcodeproj` — likely breaks ⌘U (Test) the same way Run was
broken. Not yet fixed.

## Uncommitted local changes (as of 2026-07-06)

- `surfside-ios-sample-app`: `project.pbxproj` (deployment target 18.4→18.2,
  plus Xcode auto-changed `DEVELOPMENT_TEAM`/`PRODUCT_BUNDLE_IDENTIFIER` to
  James's personal signing team — pre-existing, not done by Claude) and the
  `.xcscheme` Run fix above.
- `surfside-ios-tracker`: `Sources/Entities/LocationEntity.swift` modified
  (pre-existing edit, not made this session).
