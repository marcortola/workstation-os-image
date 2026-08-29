/*
 * workstation-x11-clipsync — event-driven X11 -> Wayland CLIPBOARD mirror.
 *
 * niri drives Xwayland through xwayland-satellite, which does not synchronise
 * the Xwayland CLIPBOARD selection into the Wayland clipboard. X11 apps (e.g.
 * the 1Password Flatpak, whose Rust core copies via X11) therefore copy but
 * Wayland apps paste nothing.
 *
 * This daemon subscribes to XFixes selection-owner notifications on CLIPBOARD
 * and, on each change, reads the selection in-process and pushes it to the
 * Wayland clipboard with wl-copy. It blocks on the X socket (zero idle CPU) and
 * only does work when the clipboard actually changes. One-directional
 * (X11 -> Wayland) so it can never fight the Wayland side; text only, by design.
 *
 * Supervision (restart on X server loss / before Xwayland is up) is handled by
 * the systemd user unit, so this stays a single connect-once event loop and
 * exits non-zero when it cannot reach the X server.
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xfixes.h>
#include <fcntl.h>
#include <stddef.h>
#include <sys/wait.h>
#include <unistd.h>

/* Run wl-copy with argv, feeding `data` (len bytes) on its stdin when non-NULL. */
static void run_wl_copy(const char *arg, const unsigned char *data, size_t len) {
    int fds[2] = {-1, -1};
    if (data && pipe(fds) != 0)
        return;

    pid_t pid = fork();
    if (pid < 0) {
        if (fds[0] != -1) { close(fds[0]); close(fds[1]); }
        return;
    }
    if (pid == 0) {
        if (data) {
            dup2(fds[0], STDIN_FILENO);
            close(fds[0]);
            close(fds[1]);
        }
        if (arg)
            execlp("wl-copy", "wl-copy", arg, (char *)NULL);
        else
            execlp("wl-copy", "wl-copy", (char *)NULL);
        _exit(127);
    }

    if (data) {
        close(fds[0]);
        for (size_t off = 0; off < len;) {
            ssize_t n = write(fds[1], data + off, len - off);
            if (n <= 0)
                break;
            off += (size_t)n;
        }
        close(fds[1]);
    }
    /* wl-copy forks a server child and its foreground process exits promptly. */
    waitpid(pid, NULL, 0);
}

/* Ask for CLIPBOARD as `target`; return the property type and the bytes
 * (free with XFree) via out and out_len, or None if nothing was produced. */
static Atom read_clipboard(Display *dpy, Window win, Atom clipboard, Atom target,
                           Atom prop, unsigned char **out, unsigned long *out_len) {
    *out = NULL;
    *out_len = 0;
    XConvertSelection(dpy, clipboard, target, prop, win, CurrentTime);

    for (;;) {
        XEvent ev;
        XNextEvent(dpy, &ev);
        if (ev.type != SelectionNotify || ev.xselection.requestor != win)
            continue; /* ignore unrelated events while awaiting the reply */
        if (ev.xselection.property == None)
            return None;

        Atom type = None;
        int format = 0;
        unsigned long nitems = 0, after = 0;
        unsigned char *value = NULL;
        if (XGetWindowProperty(dpy, win, prop, 0, 0x1FFFFFFFL, True, AnyPropertyType,
                               &type, &format, &nitems, &after, &value) != Success)
            return None;
        if (type == None || format != 8) { /* skip INCR/non-8-bit payloads */
            if (value)
                XFree(value);
            return None;
        }
        *out = value;
        *out_len = nitems;
        return type;
    }
}

int main(void) {
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy)
        return 1; /* Xwayland not up yet — systemd restarts us */

    int event_base, error_base;
    if (!XFixesQueryExtension(dpy, &event_base, &error_base))
        return 2;

    /* Don't leak the X connection into wl-copy children. */
    fcntl(ConnectionNumber(dpy), F_SETFD, FD_CLOEXEC);

    Atom clipboard = XInternAtom(dpy, "CLIPBOARD", False);
    Atom utf8 = XInternAtom(dpy, "UTF8_STRING", False);
    Atom prop = XInternAtom(dpy, "WORKSTATION_X11_CLIPSYNC", False);

    Window win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 1, 1, 0, 0, 0);
    XFixesSelectSelectionInput(dpy, win, clipboard,
                               XFixesSetSelectionOwnerNotifyMask |
                                   XFixesSelectionWindowDestroyNotifyMask |
                                   XFixesSelectionClientCloseNotifyMask);

    for (;;) {
        XEvent ev;
        XNextEvent(dpy, &ev); /* blocks: no CPU while idle */
        if (ev.type != event_base + XFixesSelectionNotify)
            continue;
        if (((XFixesSelectionNotifyEvent *)&ev)->selection != clipboard)
            continue;

        Window owner = XGetSelectionOwner(dpy, clipboard);
        if (owner == None) {
            run_wl_copy("--clear", NULL, 0); /* clipboard cleared (e.g. 1Password auto-clear) */
            continue;
        }
        if (owner == win)
            continue; /* never happens: we don't own it */

        unsigned char *data = NULL;
        unsigned long len = 0;
        Atom type = read_clipboard(dpy, win, clipboard, utf8, prop, &data, &len);
        if (type == None) {
            if (data)
                XFree(data);
            type = read_clipboard(dpy, win, clipboard, XA_STRING, prop, &data, &len);
        }
        if (type != None && data && len > 0)
            run_wl_copy(NULL, data, len);
        if (data)
            XFree(data);
    }
}
