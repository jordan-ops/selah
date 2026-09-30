/*
 * xunhide — work around Hyprland 0.56.x "hide windows sized <= 1x1" behavior.
 *
 * Hyprland's CWindow::onX11ConfigureRequest() does:
 *     if (box.size() > Vector2D{1,1}) setHidden(false); else setHidden(true);
 * but misses some configure-requests during window startup, leaving windows
 * (e.g. MEGAsync's onboarding dialog, which Qt creates at 1x1 before growing
 * it) stuck with hidden=true -> not visible, not focusable, accepts no input.
 *
 * Sending the window a tiny resize (out and back) is a real client
 * configure-request, which runs exactly the setHidden(false) branch and
 * restores visibility/input.
 *
 * usage: xunhide <title-substring>   e.g.  xunhide "Set up MEGA"
 *        xunhide --all               poke every viewable top-level window
 */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fixed = 0;

static void poke(Display* d, Window w, const char* name) {
    XWindowAttributes a;
    if (!XGetWindowAttributes(d, w, &a) || a.map_state != IsViewable)
        return;
    int ow = a.width, oh = a.height;
    XResizeWindow(d, w, ow + 2, oh + 2);
    XResizeWindow(d, w, ow, oh);
    XSync(d, False);
    printf("unhid: 0x%lx '%s' (%dx%d)\n", w, name ? name : "?", ow, oh);
    fixed++;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: xunhide <title-substring> | xunhide --all\n");
        return 2;
    }
    Display* d = XOpenDisplay(NULL);
    if (!d) { fprintf(stderr, "xunhide: cannot open display\n"); return 1; }

    Window root, parent, *kids = NULL;
    unsigned int n = 0;
    if (!XQueryTree(d, DefaultRootWindow(d), &root, &parent, &kids, &n)) {
        XCloseDisplay(d);
        return 1;
    }

    for (unsigned int i = 0; i < n; i++) {
        char* name = NULL;
        XFetchName(d, kids[i], &name);
        if (name) {
            if (strcmp(argv[1], "--all") == 0 || strstr(name, argv[1]) != NULL)
                poke(d, kids[i], name);
            XFree(name);
        }
    }
    if (kids) XFree(kids);
    XCloseDisplay(d);

    if (!fixed)
        printf("no viewable window matching '%s'\n", argv[1]);
    return fixed ? 0 : 3;
}
