# Security

AniLocal is a local desktop application. It runs unsandboxed (libmpv needs
that), reads the folders you point it at, and talks to a fixed set of public
services over HTTPS — AniList, Kitsu, Jikan, AniSkip, and GitHub for the
cross-database id map and cover images from the providers' CDNs. It has no
account, stores no credential unless you paste one for an optional source,
and never sends anything about your library anywhere. Settings → About →
Privacy lists exactly what leaves the machine.

## Reporting a vulnerability

Please report privately rather than in a public issue: open a
[GitHub security advisory](https://github.com/pngu-nerf/anilocal/security/advisories/new)
on the repository. Include the version (Settings → About), macOS version, and
steps to reproduce. You should hear back within a week.

Things that are in scope: anything that lets a file name, a container, a
subtitle, or a network response make the app do something other than play
video and show metadata — path traversal from a crafted file name, memory
safety in the hand-written MKV/MP4 chapter parsers, a metadata response that
reaches the shell or the filesystem, credential leakage.

Things that are not: the app reading folders you added (that is what it is
for), the fact that it runs unsandboxed, and the upstream media stack — libmpv,
FFmpeg and libass issues belong with those projects, though a report that
AniLocal ships a vulnerable version is welcome here.

## Supported versions

Only the latest release. There is no long-term-support branch.
