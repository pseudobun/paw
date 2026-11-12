// paw's Dock payload: loaded into Dock.app by paw-dock-loader (as root, with SIP's debugging
// restrictions off). Dock's connection to the window server may move any window, so here a
// window moves at once, without waiting for the app that owns it to answer an accessibility
// call. paw talks to it over a Unix socket only the same user can reach. SkyLight is private:
// its functions are looked up at load time in Dock, which already has it loaded.
//
// Protocol: each message is a little-endian uint32 length, then that many bytes: one opcode
// byte and its arguments. A connection stays open for many messages.
//   0x01 hello                         -> replies "paw-dock <version>\n"
//   0x02 move  u32 count, count x (u32 window, f64 x, f64 y)   (AX coordinates, no reply)
//   0x03 order u32 count, count x u32 window                   (bring to front, no reply)
//   0x04 level u32 count, i32 level, count x u32 window        (window sub-level, no reply)

#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <stdatomic.h>
#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// scripts/bundle.sh sets it to a hash of this file and loader.m.
#ifndef PAW_DOCK_VERSION
#define PAW_DOCK_VERSION "dev"
#endif
#define PAW_DOCK_MAX_MESSAGE (1 << 20)
// paw keeps one connection open; a few more for `paw dock status` and restarts.
#define PAW_DOCK_MAX_CONNECTIONS 8

extern int SLSMainConnectionID(void);
extern CGError SLSMoveWindowWithGroup(int cid, uint32_t wid, CGPoint *point);
extern CGError SLSReassociateWindowsSpacesByGeometry(int cid, CFArrayRef windows);
extern CGError SLSDisableUpdate(int cid);
extern CGError SLSReenableUpdate(int cid);
extern CGError SLSOrderWindow(int cid, uint32_t wid, int order, uint32_t relative);
extern CGError SLSSetWindowSubLevel(int cid, uint32_t wid, int level);
extern CFArrayRef SLSCopyAssociatedWindows(int cid, uint32_t wid);

static int listen_fd = -1;
static _Atomic int live = 0;

static bool read_all(int fd, void *buf, size_t len)
{
    size_t done = 0;
    while (done < len) {
        ssize_t n = read(fd, (char *)buf + done, len - done);
        if (n <= 0) return false;
        done += (size_t)n;
    }
    return true;
}

static void do_move(const uint8_t *p, size_t len)
{
    if (len < 4) return;
    uint32_t count;
    memcpy(&count, p, 4);
    p += 4; len -= 4;
    if (count == 0 || (size_t)count * 20 > len) return;

    int cid = SLSMainConnectionID();
    CFMutableArrayRef moved = CFArrayCreateMutable(NULL, count, &kCFTypeArrayCallBacks);
    // One screen update for all of them: they appear and go in the same frame.
    SLSDisableUpdate(cid);
    for (uint32_t i = 0; i < count; ++i, p += 20) {
        uint32_t wid;
        double x, y;
        memcpy(&wid, p, 4);
        memcpy(&x, p + 4, 8);
        memcpy(&y, p + 12, 8);
        CGPoint point = CGPointMake(x, y);
        if (SLSMoveWindowWithGroup(cid, wid, &point) == kCGErrorSuccess) {
            CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt32Type, &wid);
            CFArrayAppendValue(moved, n);
            CFRelease(n);
        }
    }
    SLSReenableUpdate(cid);
    // A window now on another display belongs to that display's space.
    if (CFArrayGetCount(moved) > 0) SLSReassociateWindowsSpacesByGeometry(cid, moved);
    CFRelease(moved);
}

static void do_order(const uint8_t *p, size_t len)
{
    if (len < 4) return;
    uint32_t count;
    memcpy(&count, p, 4);
    p += 4; len -= 4;
    if ((size_t)count * 4 > len) return;
    int cid = SLSMainConnectionID();
    for (uint32_t i = 0; i < count; ++i, p += 4) {
        uint32_t wid;
        memcpy(&wid, p, 4);
        SLSOrderWindow(cid, wid, 1, 0);
    }
}

// Floating windows above tiled ones (yabai's sub-layer). Sheets and other windows attached to
// one go with it; left behind at the normal level they would open behind it.
static void do_level(const uint8_t *p, size_t len)
{
    if (len < 8) return;
    uint32_t count;
    int32_t level;
    memcpy(&count, p, 4);
    memcpy(&level, p + 4, 4);
    p += 8; len -= 8;
    if ((size_t)count * 4 > len) return;
    int cid = SLSMainConnectionID();
    for (uint32_t i = 0; i < count; ++i, p += 4) {
        uint32_t wid;
        memcpy(&wid, p, 4);
        SLSSetWindowSubLevel(cid, wid, level);
        CFArrayRef attached = SLSCopyAssociatedWindows(cid, wid);
        if (!attached) continue;
        for (CFIndex j = 0; j < CFArrayGetCount(attached); ++j) {
            CFNumberRef n = CFArrayGetValueAtIndex(attached, j);
            uint32_t child;
            if (n && CFGetTypeID(n) == CFNumberGetTypeID() && CFNumberGetValue(n, kCFNumberSInt32Type, &child) && child != wid)
                SLSSetWindowSubLevel(cid, child, level);
        }
        CFRelease(attached);
    }
}

static void *serve(void *arg)
{
    int fd = (int)(intptr_t)arg;
    uint8_t *buf = malloc(PAW_DOCK_MAX_MESSAGE);
    for (; buf;) {
        uint32_t len;
        if (!read_all(fd, &len, 4) || len == 0 || len > PAW_DOCK_MAX_MESSAGE) break;
        if (!read_all(fd, buf, len)) break;
        @autoreleasepool {
            switch (buf[0]) {
            case 0x01: {
                const char *hello = "paw-dock " PAW_DOCK_VERSION "\n";
                write(fd, hello, strlen(hello));
            } break;
            case 0x02: do_move(buf + 1, len - 1); break;
            case 0x03: do_order(buf + 1, len - 1); break;
            case 0x04: do_level(buf + 1, len - 1); break;
            default: break;
            }
        }
    }
    free(buf);
    close(fd);
    atomic_fetch_sub(&live, 1);
    return NULL;
}

static void *accept_loop(void *unused)
{
    for (;;) {
        int fd = accept(listen_fd, NULL, NULL);
        if (fd < 0) {
            // Out of descriptors: wait for one instead of spinning inside Dock.
            if (errno == EMFILE || errno == ENFILE || errno == ENOMEM) usleep(50000);
            continue;
        }
        // Only the user Dock runs as.
        uid_t uid; gid_t gid;
        if (getpeereid(fd, &uid, &gid) != 0 || uid != getuid()) { close(fd); continue; }
        if (atomic_fetch_add(&live, 1) >= PAW_DOCK_MAX_CONNECTIONS) { atomic_fetch_sub(&live, 1); close(fd); continue; }
        // A client that resets the connection must not take Dock down with SIGPIPE. An idle
        // connection is dropped after 5 minutes (paw reconnects by itself).
        // (A connection already reset can refuse the option: drop it before writing to it.)
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one) != 0) {
            close(fd); atomic_fetch_sub(&live, 1); continue;
        }
        struct timeval idle = { .tv_sec = 300 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &idle, sizeof idle);
        pthread_t t;
        if (pthread_create(&t, NULL, serve, (void *)(intptr_t)fd) == 0) pthread_detach(t);
        else { close(fd); atomic_fetch_sub(&live, 1); }
    }
    return NULL;
}

__attribute__((constructor))
static void paw_dock_load(void)
{
    // In the user's own temporary directory (0700, per user), not /tmp: there another user
    // could take the name first and keep the helper from listening, or pose as it.
    char dir[PATH_MAX], path[104];
    size_t n = confstr(_CS_DARWIN_USER_TEMP_DIR, dir, sizeof(dir));
    if (n == 0 || n > sizeof(dir)) { NSLog(@"[paw-dock] no user temporary directory"); return; }
    struct stat st;
    if (lstat(dir, &st) != 0 || !S_ISDIR(st.st_mode) || st.st_uid != getuid() || (st.st_mode & 077)) {
        NSLog(@"[paw-dock] %s is not a private directory", dir);
        return;
    }
    if (snprintf(path, sizeof(path), "%s%spaw-dock.sock", dir, dir[strlen(dir) - 1] == '/' ? "" : "/") >= (int)sizeof(path)) {
        NSLog(@"[paw-dock] socket path too long");
        return;
    }
    if (unlink(path) != 0 && errno != ENOENT) { NSLog(@"[paw-dock] could not remove %s", path); return; }
    listen_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listen_fd < 0) return;
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    strlcpy(addr.sun_path, path, sizeof(addr.sun_path));
    mode_t old = umask(0077);
    int ok = bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr));
    umask(old);
    if (ok != 0 || chmod(path, 0600) != 0 || listen(listen_fd, 8) != 0) {
        close(listen_fd);
        listen_fd = -1;
        NSLog(@"[paw-dock] could not listen on %s", path);
        return;
    }
    pthread_t t;
    pthread_create(&t, NULL, accept_loop, NULL);
    pthread_detach(t);
    NSLog(@"[paw-dock] listening on %s", path);
}
