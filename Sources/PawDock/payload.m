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

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define PAW_DOCK_VERSION "1"
#define PAW_DOCK_MAX_MESSAGE (1 << 20)

extern int SLSMainConnectionID(void);
extern CGError SLSMoveWindowWithGroup(int cid, uint32_t wid, CGPoint *point);
extern CGError SLSReassociateWindowsSpacesByGeometry(int cid, CFArrayRef windows);
extern CGError SLSDisableUpdate(int cid);
extern CGError SLSReenableUpdate(int cid);
extern CGError SLSOrderWindow(int cid, uint32_t wid, int order, uint32_t relative);

static int listen_fd = -1;

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

static void *serve(void *arg)
{
    int fd = (int)(intptr_t)arg;
    uint8_t *buf = malloc(PAW_DOCK_MAX_MESSAGE);
    for (;;) {
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
            default: break;
            }
        }
    }
    free(buf);
    close(fd);
    return NULL;
}

static void *accept_loop(void *unused)
{
    for (;;) {
        int fd = accept(listen_fd, NULL, NULL);
        if (fd < 0) continue;
        // Only the user Dock runs as.
        uid_t uid; gid_t gid;
        if (getpeereid(fd, &uid, &gid) != 0 || uid != getuid()) { close(fd); continue; }
        pthread_t t;
        if (pthread_create(&t, NULL, serve, (void *)(intptr_t)fd) == 0) pthread_detach(t);
        else close(fd);
    }
    return NULL;
}

__attribute__((constructor))
static void paw_dock_load(void)
{
    char path[104];
    snprintf(path, sizeof(path), "/tmp/paw-dock-%u.sock", getuid());
    unlink(path);
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
