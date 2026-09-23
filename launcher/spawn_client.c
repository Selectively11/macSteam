// posix_spawns the UNBUNDLED steam_osx (flags=0x0, honors DYLD_INSERT unlike the lame .app) with
// STEAM_APP_BUNDLE_PATH=stub so sub_10002BDD2 skips its auto-update bullshit
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/wait.h>
#include <pwd.h>
#include <errno.h>
#include <limits.h>
#include <libgen.h>
#include <sys/stat.h>
#include <dirent.h>
#include <mach-o/dyld.h>

extern char **environ;


#ifndef SX_BUNDLE_SUFFIX
#define SX_BUNDLE_SUFFIX "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
#endif

#ifndef SX_STATE_SUFFIX
#define SX_STATE_SUFFIX "/Library/Application Support/macsteam"
#endif
#ifndef SX_DYLIB_SUFFIX
#define SX_DYLIB_SUFFIX SX_STATE_SUFFIX "/macsteam.dylib"
#endif
#ifndef SX_LOG_SUFFIX
#define SX_LOG_SUFFIX SX_STATE_SUFFIX "/launcher.log"
#endif
#ifndef SX_SIG_DIR_SUFFIX
#define SX_SIG_DIR_SUFFIX SX_STATE_SUFFIX "/signatures/macos.arm64"
#endif
#ifndef SX_STUB_BUNDLE
#define SX_STUB_BUNDLE "/Applications/Steam.app"
#endif

#ifndef SX_WRAPPER_SUFFIX
#define SX_WRAPPER_SUFFIX SX_STATE_SUFFIX "/Steam.app"
#endif

static const char *STUB_BUNDLE = SX_STUB_BUNDLE;


static const char *home_dir(void) {
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_dir && pw->pw_dir[0]) return pw->pw_dir;
    const char *h = getenv("HOME");
    return (h && h[0]) ? h : "/tmp";
}

static void ts(FILE *f);


static void mkdir_p(const char *path) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = '\0'; mkdir(tmp, 0755); *p = '/'; }
    }
    mkdir(tmp, 0755);
}

static int read_text(const char *path, char *buf, size_t n) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    size_t got = fread(buf, 1, n - 1, f);
    fclose(f);
    buf[got] = '\0';
    while (got && (buf[got - 1] == '\n' || buf[got - 1] == ' ' || buf[got - 1] == '\t'))
        buf[--got] = '\0';
    return 0;
}


// Write to a temp beside dst and rename in, so a partial write never leaves a
// truncated file at dst (a truncated macsteam.dylib would be DYLD-inserted and
// fail the next launch).
static int copy_file(const char *src, const char *dst) {
    FILE *in = fopen(src, "rb");
    if (!in) return -1;

    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s.tmpXXXXXX", dst);
    int fd = mkstemp(tmp);
    if (fd < 0) { fclose(in); return -1; }
    fchmod(fd, 0644);   // mkstemp is 0600; match a plain create so readers aren't surprised
    FILE *out = fdopen(fd, "wb");
    if (!out) { close(fd); unlink(tmp); fclose(in); return -1; }

    char b[65536]; size_t r; int rc = 0;
    while ((r = fread(b, 1, sizeof b, in)) > 0)
        if (fwrite(b, 1, r, out) != r) { rc = -1; break; }
    if (ferror(in)) rc = -1;
    fclose(in);
    if (fclose(out) != 0) rc = -1;

    if (rc == 0 && rename(tmp, dst) != 0) rc = -1;
    if (rc != 0) unlink(tmp);
    return rc;
}


static int bundle_resource(const char *name, char *out, size_t n) {
    char exe[PATH_MAX]; uint32_t sz = sizeof exe;
    if (_NSGetExecutablePath(exe, &sz) != 0) return -1;
    char real[PATH_MAX];
    if (!realpath(exe, real)) return -1;
    char *macos = dirname(real);
    char contents[PATH_MAX];
    snprintf(contents, sizeof contents, "%s", macos);
    char *c = dirname(contents);
    snprintf(out, n, "%s/Resources/%s", c, name);
    return 0;
}


static void deploy_bundled_signatures(const char *home, FILE *log) {
    char srcdir[PATH_MAX];
    if (bundle_resource("signatures", srcdir, sizeof srcdir) != 0) return;
    DIR *d = opendir(srcdir);
    if (!d) return;   // not a bundled build

    char dstdir[PATH_MAX];
    snprintf(dstdir, sizeof dstdir, "%s" SX_SIG_DIR_SUFFIX, home);
    mkdir_p(dstdir);

    int n = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        size_t nl = strlen(ent->d_name);
        if (nl < 6 || strcmp(ent->d_name + nl - 5, ".json") != 0) continue;
        char src[PATH_MAX], dst[PATH_MAX];
        snprintf(src, sizeof src, "%s/%s", srcdir, ent->d_name);
        snprintf(dst, sizeof dst, "%s/%s", dstdir, ent->d_name);
        if (copy_file(src, dst) == 0) n++;
        else { ts(log); fprintf(log, "ERROR deploying %s: %s\n", dst, strerror(errno)); }
    }
    closedir(d);
    ts(log); fprintf(log, "deployed %d signature profiles -> %s\n", n, dstdir); fflush(log);
}

static void deploy_bundled_dylib(const char *home, char *out, size_t n, FILE *log) {
    char dir[PATH_MAX], dst[PATH_MAX], dst_ver[PATH_MAX];
    snprintf(dir, sizeof dir, "%s" SX_STATE_SUFFIX, home);
    snprintf(dst, sizeof dst, "%s/macsteam.dylib", dir);
    snprintf(dst_ver, sizeof dst_ver, "%s/macsteam.dylib.version", dir);
    snprintf(out, n, "%s", dst);

    char src[PATH_MAX], src_ver[PATH_MAX];
    if (bundle_resource("macsteam.dylib", src, sizeof src) != 0 ||
        bundle_resource("macsteam.dylib.version", src_ver, sizeof src_ver) != 0) {
        ts(log); fprintf(log, "no bundled dylib. Using deployed %s\n", dst); fflush(log);
        return;
    }
    struct stat st;
    if (stat(src, &st) != 0) {
        ts(log); fprintf(log, "no bundled dylib at %s. Using deployed\n", src); fflush(log);
        return;
    }

    // A failed read leaves the buffer empty, so an unreadable dest version reads as
    // "not current" and redeploys (the safe direction).
    char bv[64] = "", dv[64] = "";
    if (read_text(src_ver, bv, sizeof bv) != 0) bv[0] = '\0';
    if (read_text(dst_ver, dv, sizeof dv) != 0) dv[0] = '\0';

    // Signatures missing? deploy even when the dylib itself is "current".
    char sigdir[PATH_MAX];
    snprintf(sigdir, sizeof sigdir, "%s" SX_SIG_DIR_SUFFIX, home);
    int sig_missing = (stat(sigdir, &st) != 0);

    if (bv[0] && strcmp(bv, dv) == 0 && !sig_missing) {
        ts(log); fprintf(log, "dylib up to date (v%s)\n", dv); fflush(log);
        return;
    }

    mkdir_p(dir);
    if (copy_file(src, dst) == 0) {
        copy_file(src_ver, dst_ver);
        ts(log); fprintf(log, "deployed dylib v%s (was v%s)\n",
                          bv[0] ? bv : "?", dv[0] ? dv : "none"); fflush(log);
    } else {
        ts(log); fprintf(log, "ERROR deploying dylib to %s: %s\n",
                          dst, strerror(errno)); fflush(log);
    }
    deploy_bundled_signatures(home, log);
}

static int relink(const char *target, const char *dst) {
    unlink(dst);
    return symlink(target, dst);
}

// Clean wrapper bundle we spawn steam_osx through, rebuilt idempotently each launch.
//
// The Dock realizes a process's tile against the bundle that contains its
// executable path (_NSGetExecutablePath, symlinks NOT resolved). The inner
// AppBundle carries a stale custom-icon override (FinderInfo kHasCustomIcon +
// Icon\r) from a prior real Steam launch, so realizing against it paints the
// legacy icon before anything runs. This wrapper has no such override, and its
// Resources/Assets.car is the same catalog holding the glass icon, so realizing
// against it paints glass from the first frame.
//
// Everything is symlinks into the inner bundle (no Steam-bundle writes, no copies
// to drift): Contents/MacOS -> inner MacOS (steam_osx itself, all dylibs, the
// runtime tree), Contents/Resources/Assets.car -> inner glass catalog. Only
// Info.plist is copied (a plain file, needed so CFBundle treats the dir as a
// bundle). Rebuilt every launch so it tracks Steam updates. Spawning
// <wrapper>/Contents/MacOS/steam_osx keeps that path (the MacOS symlink component
// is not collapsed), so CFBundle walks up to the wrapper, not the inner bundle.
static int build_glass_wrapper(const char *home, const char *inner_contents,
                               char *out_exe, size_t n, FILE *log) {
    char wrap[PATH_MAX];
    snprintf(wrap, sizeof wrap, "%s" SX_WRAPPER_SUFFIX, home);

    char c[PATH_MAX], res[PATH_MAX];
    snprintf(c, sizeof c, "%s/Contents", wrap);
    snprintf(res, sizeof res, "%s/Resources", c);
    mkdir_p(res);

    char src[PATH_MAX], dst[PATH_MAX];

    // Info.plist: copy (CFBundle needs a real file here to recognize the bundle).
    snprintf(src, sizeof src, "%s/Info.plist", inner_contents);
    snprintf(dst, sizeof dst, "%s/Info.plist", c);
    if (copy_file(src, dst) != 0) {
        ts(log); fprintf(log, "ERROR wrapper Info.plist copy: %s\n", strerror(errno));
        fflush(log);
        return -1;
    }

    snprintf(src, sizeof src, "%s/MacOS", inner_contents);
    snprintf(dst, sizeof dst, "%s/MacOS", c);
    if (relink(src, dst) != 0) {
        ts(log); fprintf(log, "ERROR wrapper MacOS symlink: %s\n", strerror(errno));
        fflush(log);
        return -1;
    }

    snprintf(src, sizeof src, "%s/Resources/Assets.car", inner_contents);
    snprintf(dst, sizeof dst, "%s/Assets.car", res);
    if (relink(src, dst) != 0) {
        ts(log); fprintf(log, "ERROR wrapper Assets.car symlink: %s\n", strerror(errno));
        fflush(log);
        return -1;
    }

    snprintf(out_exe, n, "%s/MacOS/steam_osx", c);
    ts(log); fprintf(log, "glass wrapper ready: %s\n", wrap); fflush(log);
    return 0;
}

static void ts(FILE *f) {
    time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    char buf[32];
    strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S", &tm);
    fprintf(f, "[%s] ", buf);
}

static void run_wait(char *const av[]) {
    pid_t p;
    if (posix_spawn(&p, av[0], NULL, NULL, av, environ) == 0) {
        int st;
        waitpid(p, &st, 0);
    }
}

static void run_pkill(const char *flag, const char *pat) {
    char *av[] = { "/usr/bin/pkill", (char *)flag, (char *)pat, NULL };
    run_wait(av);
}

// Slap Steam's KeepAlive ipctool launchd agent, pkill can't beat KeepAlive
// (launchd resurrects a stale ipcserver holding the mach name a fresh steam_osx session needs).
static void bootout_ipc_agent(FILE *log) {
    char domain[64];
    snprintf(domain, sizeof domain, "user/%u/com.valvesoftware.steam.ipctool",
             (unsigned)getuid());
    char *av[] = { "/bin/launchctl", "bootout", domain, NULL };
    run_wait(av);
    ts(log); fprintf(log, "bootout %s\n", domain); fflush(log);
}

// An orphaned ipcserver breaks later launches.
static void prekill(FILE *log) {
    const char *fpats[] = {
        "Steam.AppBundle", "Steam Helper", "ipcserver",
        "steamwebhelper", "Frameworks/Steam", NULL
    };
    // Slap the KeepAlive agent first so launchd stops resurrecting ipcserver
    bootout_ipc_agent(log);
    for (int r = 0; r < 3; r++) {
        run_pkill("-x", "steam_osx");
        for (int i = 0; fpats[i]; i++) run_pkill("-f", fpats[i]);
        usleep(500000);
    }
    // Once more. A mach lookup mid-sweep can re-launch the agent, and the IPC namespace has to be clean.
    bootout_ipc_agent(log);
    run_pkill("-f", "ipcserver");
    ts(log); fprintf(log, "prekill sweep complete\n"); fflush(log);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    const char *home = home_dir();
    char bundle_macos[PATH_MAX], exe[PATH_MAX], dylib[PATH_MAX], log_path[PATH_MAX];
    char state_dir[PATH_MAX];
    snprintf(bundle_macos, sizeof bundle_macos, "%s%s", home, SX_BUNDLE_SUFFIX);
    snprintf(exe, sizeof exe, "%s/steam_osx", bundle_macos);
    snprintf(state_dir, sizeof state_dir, "%s" SX_STATE_SUFFIX, home);
    snprintf(log_path, sizeof log_path, "%s%s", home, SX_LOG_SUFFIX);
    mkdir_p(state_dir);

    FILE *log = fopen(log_path, "a");
    if (!log) log = stderr;

    const char *dylib_env = getenv("MACSTEAM_DYLIB");
    if (dylib_env && dylib_env[0]) {
        snprintf(dylib, sizeof dylib, "%s", dylib_env);
    } else {
        deploy_bundled_dylib(home, dylib, sizeof dylib, log);
    }
    const char *BUNDLE_MACOS = bundle_macos;
    const char *EXE = exe;
    const char *DYLIB = dylib;

    struct passwd *pw = getpwuid(getuid());
    ts(log);
    fprintf(log, "launcher start: uid=%d euid=%d user=%s\n",
            getuid(), geteuid(), pw ? pw->pw_name : "?");
    fflush(log);

    // Refuse root: Steam's own start() bails hard on geteuid()==0. Guards accidental sudo.
    if (geteuid() == 0) {
        ts(log);
        fprintf(log, "ERROR: running as root (euid=0). Client would Shutdown. "
                     "Launch via GUI/Finder as the console user.\n");
        fflush(log);
        return 4;
    }

    prekill(log);

    if (chdir(BUNDLE_MACOS) != 0) {
        ts(log); fprintf(log, "ERROR chdir(%s): %s\n", BUNDLE_MACOS, strerror(errno));
        fflush(log);
        perror("chdir");
        return 2;
    }

    setenv("DYLD_INSERT_LIBRARIES", DYLIB, 1);
    // STEAM_APP_BUNDLE_PATH=stub. sub_10002BDD2 sees it set and skips unbundle+execv
    // (dylib stays loaded) and takes the "No update necessary" branch. So much silly shit to avoid
    // having to modify the app bundle...
    setenv("STEAM_APP_BUNDLE_PATH", STUB_BUNDLE, 1);

    char inner_contents[PATH_MAX], wrap_exe[PATH_MAX], macos_copy[PATH_MAX];
    snprintf(macos_copy, sizeof macos_copy, "%s", BUNDLE_MACOS);
    snprintf(inner_contents, sizeof inner_contents, "%s", dirname(macos_copy));
    const char *SPAWN_EXE = EXE;
    if (build_glass_wrapper(home, inner_contents, wrap_exe, sizeof wrap_exe, log) == 0)
        SPAWN_EXE = wrap_exe;

    // argv[0] basename has to be "steam_osx" so sx_init's getprogname() gate matches
    // and the dylib activates.
    char *child_argv[] = { (char *)SPAWN_EXE, NULL };

    // posix_spawn (not execv): spawned steam_osx daemonizes (ppid=1) into the
    // long-lived client. execv with this env made it dlclose+exit without login.
    pid_t pid = 0;
    int rc = posix_spawn(&pid, SPAWN_EXE, NULL, NULL, child_argv, environ);
    if (rc != 0) {
        ts(log); fprintf(log, "ERROR posix_spawn(%s): %s\n", SPAWN_EXE, strerror(rc));
        fflush(log);
        fprintf(stderr, "posix_spawn: %s\n", strerror(rc));
        return 3;
    }
    ts(log);
    fprintf(log, "spawned steam_osx pid=%d exe=%s DYLD_INSERT=%s STEAM_APP_BUNDLE_PATH=%s\n",
            pid, SPAWN_EXE, DYLIB, STUB_BUNDLE);
    fflush(log);
    printf("spawned steam_osx pid=%d\n", pid);
    return 0;
}
