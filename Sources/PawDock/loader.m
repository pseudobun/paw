// paw-dock-loader: puts paw's Dock payload into Dock.app. Needs root and SIP's debugging
// restrictions off (task_for_pid on Dock), plus the -arm64e_preview_abi boot-arg on Apple
// silicon (Dock is arm64e).
//
//   paw-dock-loader <payload.dylib>           every running Dock, once
//   paw-dock-loader --watch <payload.dylib>   and again whenever a Dock starts (the launch
//                                             daemon `paw dock install` sets up runs this)
//
// The payload must be owned by root and writable by no one else: whatever it is runs inside
// Dock, so a file another user (or the user's own processes) could swap is refused.
//
// :Attribution
// The remote-thread technique (a stub that calls pthread_create_from_mach_thread, whose thread
// dlopens the payload) follows yabai's loader (MIT, Åsmund Vikane), whose arm64e path is based
// on work by Jeremy Legendre (https://github.com/jslegendre).

#include <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <libproc.h>
#include <ptrauth.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef __arm64__
#error paw-dock-loader is built for Apple silicon only
#endif

static kern_return_t (*convert_thread_state)(thread_act_t, int, thread_state_flavor_t, thread_state_t,
                                             mach_msg_type_number_t, thread_state_t, mach_msg_type_number_t *);

// A stub run on a bare mach thread: makes a real pthread (dlopen needs one) and parks itself,
// leaving 0x79616265 in x0 so the loader knows it got that far. The pthread dlopens the path.
static char shell_code[] =
"\xFF\xC3\x00\xD1" "\xFD\x7B\x02\xA9" "\xFD\x83\x00\x91" "\xA0\xC3\x1F\xB8"
"\xE1\x0B\x00\xF9" "\xE0\x23\x00\x91" "\x08\x00\x80\xD2" "\xE8\x07\x00\xF9"
"\xE1\x03\x08\xAA" "\xE2\x01\x00\x10" "\xE2\x23\xC1\xDA" "\xE3\x03\x08\xAA"
"\x49\x01\x00\x10" "\x29\x01\x40\xF9" "\x20\x01\x3F\xD6" "\xA0\x4C\x8C\xD2"
"\x20\x2C\xAF\xF2" "\x09\x00\x00\x10" "\x20\x01\x1F\xD6" "\xFD\x7B\x42\xA9"
"\xFF\xC3\x00\x91" "\xC0\x03\x5F\xD6"
"\x00\x00\x00\x00\x00\x00\x00\x00"  // pthread_create_from_mach_thread (offset 88)
"\x7F\x23\x03\xD5" "\xFF\xC3\x00\xD1" "\xFD\x7B\x02\xA9" "\xFD\x83\x00\x91"
"\xA0\xC3\x1F\xB8" "\xE1\x0B\x00\xF9" "\x21\x00\x80\xD2" "\x60\x01\x00\x10"
"\x09\x01\x00\x10" "\x29\x01\x40\xF9" "\x20\x01\x3F\xD6" "\x09\x00\x80\x52"
"\xE0\x03\x09\xAA" "\xFD\x7B\x42\xA9" "\xFF\xC3\x00\x91" "\xFF\x0F\x5F\xD6"
"\x00\x00\x00\x00\x00\x00\x00\x00"  // dlopen (offset 160)
// the payload's path (offset 168), up to 255 bytes and a NUL
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

static const char *dock_path = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock";

/// Every Dock running (one per logged-in user).
static int dock_pids(pid_t *out, int max)
{
    int n = proc_listallpids(NULL, 0);
    if (n <= 0) return 0;
    pid_t *all = calloc((size_t)n + 64, sizeof(pid_t));
    n = proc_listallpids(all, (int)(((size_t)n + 64) * sizeof(pid_t)));
    int found = 0;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = 0; i < n && found < max; ++i) {
        if (proc_pidpath(all[i], path, sizeof(path)) > 0 && strcmp(path, dock_path) == 0) out[found++] = all[i];
    }
    free(all);
    return found;
}

static int fail(const char *what, kern_return_t kr)
{
    fprintf(stderr, "paw-dock-loader: %s%s%s\n", what, kr ? ": " : "", kr ? mach_error_string(kr) : "");
    return 1;
}

static bool payload_ok(const char *payload)
{
    struct stat st;
    if (stat(payload, &st) != 0) { fail("payload not found", 0); return false; }
    if (st.st_uid != 0 || (st.st_mode & (S_IWGRP | S_IWOTH))) {
        fail("payload must be owned by root and not writable by others", 0);
        return false;
    }
    return true;
}

static int inject(pid_t pid, const char *payload)
{
        mach_port_t task = 0;
        kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
        if (kr != KERN_SUCCESS) return fail("no task port for Dock (root, and SIP debugging restrictions off?)", kr);

        mach_vm_address_t stack = 0, code = 0;
        vm_size_t stack_size = 16 * 1024;
        uint64_t sentinel = 0xCAFEBABE;
        if ((kr = mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE))) return fail("allocate stack", kr);
        if ((kr = mach_vm_write(task, stack, (vm_address_t)&sentinel, sizeof(sentinel)))) return fail("write stack", kr);
        if ((kr = vm_protect(task, stack, stack_size, 1, VM_PROT_READ | VM_PROT_WRITE))) return fail("protect stack", kr);

        char code_buf[sizeof(shell_code)];
        memcpy(code_buf, shell_code, sizeof(shell_code));
        if ((kr = mach_vm_allocate(task, &code, sizeof(code_buf), VM_FLAGS_ANYWHERE))) return fail("allocate code", kr);
        uint64_t pcfmt = (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "pthread_create_from_mach_thread"), ptrauth_key_function_pointer);
        uint64_t dl = (uint64_t)ptrauth_strip(dlsym(RTLD_DEFAULT, "dlopen"), ptrauth_key_function_pointer);
        memcpy(code_buf + 88, &pcfmt, 8);
        memcpy(code_buf + 160, &dl, 8);
        memcpy(code_buf + 168, payload, strlen(payload) + 1);
        if ((kr = mach_vm_write(task, code, (vm_address_t)code_buf, sizeof(code_buf)))) return fail("write code", kr);
        if ((kr = vm_protect(task, code, sizeof(code_buf), 0, VM_PROT_EXECUTE | VM_PROT_READ))) return fail("protect code", kr);

        if (!convert_thread_state) {
            void *kernel = dlopen("/usr/lib/system/libsystem_kernel.dylib", RTLD_GLOBAL | RTLD_LAZY);
            if (kernel) convert_thread_state = dlsym(kernel, "thread_convert_thread_state");
        }
        if (!convert_thread_state) return fail("thread_convert_thread_state not found", 0);

        arm_thread_state64_t state = {}, machine = {};
        mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT, machine_count = ARM_THREAD_STATE64_COUNT;
        __darwin_arm_thread_state64_set_pc_fptr(state, ptrauth_sign_unauthenticated((void *)code, ptrauth_key_asia, 0));
        __darwin_arm_thread_state64_set_sp(state, stack + stack_size / 2);

        thread_act_t thread = 0;
        if ((kr = thread_create(task, &thread))) return fail("create thread", kr);
        kr = convert_thread_state(thread, 2, ARM_THREAD_STATE64, (thread_state_t)&state, count, (thread_state_t)&machine, &machine_count);
        thread_terminate(thread);
        if (kr) return fail("convert thread state", kr);
        if ((kr = thread_create_running(task, ARM_THREAD_STATE64, (thread_state_t)&machine, machine_count, &thread))) return fail("start thread", kr);

        int result = 1;
        usleep(10000);
        for (int i = 0; i < 50; ++i) {
            count = ARM_THREAD_STATE64_COUNT;
            if (thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&state, &count) != KERN_SUCCESS) break;
            if (state.__x[0] == 0x79616265) { result = 0; break; }
            usleep(20000);
        }
        thread_terminate(thread);
        mach_port_deallocate(mach_task_self(), task);
        if (result) fprintf(stderr, "paw-dock-loader: the payload did not report back (Dock %d)\n", pid);
        return result;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        bool watch = argc == 3 && strcmp(argv[1], "--watch") == 0;
        if (!(argc == 2 || watch)) { fprintf(stderr, "usage: paw-dock-loader [--watch] <payload.dylib>\n"); return 64; }
        const char *payload = argv[argc - 1];
        if (payload[0] != '/' || strlen(payload) > 255) return fail("payload path must be absolute and at most 255 bytes", 0);
        if (!payload_ok(payload)) return 1;

        pid_t pids[16];
        if (!watch) {
            int n = dock_pids(pids, 16), result = n ? 0 : fail("Dock is not running", 0);
            for (int i = 0; i < n; ++i) result |= inject(pids[i], payload);
            return result;
        }
        // Each Dock once, a couple of seconds after it appears (so it's done launching); a
        // Dock that restarts (killall Dock, a crash, logging in) is a new pid.
        pid_t done[64] = {0};
        int tries[64] = {0};
        int ndone = 0;
        for (;;) {
            int n = dock_pids(pids, 16);
            for (int i = 0; i < n; ++i) {
                int k = 0;
                while (k < ndone && done[k] != pids[i]) k++;
                if (k == ndone) {
                    if (ndone == 64) { memmove(done, done + 32, 32 * sizeof(pid_t)); memmove(tries, tries + 32, 32 * sizeof(int)); ndone = 32; k = ndone; }
                    done[ndone] = pids[i]; tries[ndone] = -1; ndone++;
                    continue;  // seen for the first time: wait one round
                }
                if (tries[k] == -1 || (tries[k] > 0 && tries[k] < 3)) {
                    if (!payload_ok(payload)) break;
                    int r = inject(pids[i], payload);
                    tries[k] = r == 0 ? 0 : (tries[k] == -1 ? 1 : tries[k] + 1);
                    if (r == 0) fprintf(stderr, "paw-dock-loader: loaded into Dock %d\n", pids[i]);
                }
            }
            sleep(2);
        }
    }
}
