// SPDX-License-Identifier: GPL-2.0-only
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include <wayland-server-core.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/version.h>
#include <wlr/xwayland/xwayland.h>

#if !defined(CYSHELL_LABWC_SUPPORTED_VERSION) || \
        !defined(CYSHELL_WLROOTS_ABI_MAJOR) || \
        !defined(CYSHELL_WLROOTS_ABI_MINOR)
#error "Build the bridge with the compatibility.conf declarations"
#endif
#if WLR_VERSION_MAJOR != CYSHELL_WLROOTS_ABI_MAJOR || \
        WLR_VERSION_MINOR != CYSHELL_WLROOTS_ABI_MINOR
#error "wlroots headers do not match the declared adapter ABI"
#endif

#define CYSHELL_LABWC_BRIDGE_API 1
#define CYSHELL_LABWC_CLIENTS 16
#define CYSHELL_LABWC_RX 8192

enum bridge_window_kind {
    BRIDGE_XDG,
    BRIDGE_XWAYLAND,
};

struct bridge_window {
    struct wl_list link;
    uint64_t id;
    enum bridge_window_kind kind;
    union {
        struct wlr_xdg_toplevel *xdg;
        struct wlr_xwayland_surface *xwayland;
    } handle;

    struct wl_listener destroy;
    struct wl_listener map;
    struct wl_listener unmap;
    struct wl_listener set_title;
    struct wl_listener set_app_id_or_class;
    struct wl_listener associate;
    struct wl_listener dissociate;
};

struct bridge_client {
    int fd;
    struct wl_event_source *source;
    bool subscribed;
    char rx[CYSHELL_LABWC_RX];
    size_t used;
};

struct bridge_xdg_hook {
    struct wl_listener new_toplevel;
};

struct bridge_xwayland_hook {
    struct wl_listener new_surface;
};

struct bridge_cursor {
    struct wl_list link;
    struct wlr_cursor *cursor;
    struct wlr_output_layout *layout;
};

static struct wl_list bridge_windows;
static struct wl_list bridge_cursors;
static uint64_t bridge_next_window_id = 1;
static struct bridge_client bridge_clients[CYSHELL_LABWC_CLIENTS];
static struct bridge_xdg_hook *bridge_xdg_hook;
static struct bridge_xwayland_hook *bridge_xwayland_hook;

static bool bridge_candidate;
static bool bridge_enabled;
static int bridge_listen_fd = -1;
static struct wl_event_source *bridge_listen_source;
static char bridge_socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static void
bridge_log(const char *level, const char *message)
{
    fprintf(stderr, "[CyShell LabWC Bridge] %s: %s\n", level, message);
}

static bool
bridge_process_is_labwc(void)
{
    char path[512] = {0};
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (n <= 0) {
        return false;
    }
    path[n] = '\0';
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "labwc") == 0;
}

static void
listener_init(struct wl_listener *listener)
{
    wl_list_init(&listener->link);
}

static bool
listener_attached(struct wl_listener *listener)
{
    return listener->link.next != &listener->link;
}

static void
listener_detach(struct wl_listener *listener)
{
    if (listener_attached(listener)) {
        wl_list_remove(&listener->link);
        wl_list_init(&listener->link);
    }
}

static struct bridge_cursor *
bridge_find_cursor(struct wlr_cursor *cursor)
{
    struct bridge_cursor *state;
    wl_list_for_each(state, &bridge_cursors, link) {
        if (state->cursor == cursor) {
            return state;
        }
    }
    return NULL;
}

static void
bridge_forget_output_layout(struct wlr_output_layout *layout)
{
    struct bridge_cursor *state;
    wl_list_for_each(state, &bridge_cursors, link) {
        if (state->layout == layout) {
            state->layout = NULL;
        }
    }
}

static void
json_escape(FILE *f, const char *s)
{
    fputc('"', f);
    if (s) {
        for (; *s; ++s) {
            unsigned char c = (unsigned char)*s;
            switch (c) {
            case '"':
            case '\\':
                fprintf(f, "\\%c", c);
                break;
            case '\b':
                fputs("\\b", f);
                break;
            case '\f':
                fputs("\\f", f);
                break;
            case '\n':
                fputs("\\n", f);
                break;
            case '\r':
                fputs("\\r", f);
                break;
            case '\t':
                fputs("\\t", f);
                break;
            default:
                if (c < 0x20) {
                    fprintf(f, "\\u%04x", c);
                } else {
                    fputc(c, f);
                }
                break;
            }
        }
    }
    fputc('"', f);
}

static bool
json_get_value(const char *json, const char *key, char *out, size_t cap)
{
    if (!json || !key || !out || cap == 0) {
        return false;
    }

    char needle[128];
    if (snprintf(needle, sizeof(needle), "\"%s\"", key) >= (int)sizeof(needle)) {
        return false;
    }

    const char *p = strstr(json, needle);
    if (!p) {
        return false;
    }
    p += strlen(needle);
    p = strchr(p, ':');
    if (!p) {
        return false;
    }
    ++p;
    while (*p == ' ' || *p == '\t') {
        ++p;
    }

    size_t i = 0;
    if (*p == '"') {
        ++p;
        while (*p && *p != '"' && i + 1 < cap) {
            if (*p == '\\' && p[1]) {
                ++p;
                switch (*p) {
                case 'n': out[i++] = '\n'; break;
                case 'r': out[i++] = '\r'; break;
                case 't': out[i++] = '\t'; break;
                default: out[i++] = *p; break;
                }
                ++p;
            } else {
                out[i++] = *p++;
            }
        }
    } else {
        while (*p && *p != ',' && *p != '}' && *p != '\n' && i + 1 < cap) {
            out[i++] = *p++;
        }
        while (i > 0 && (out[i - 1] == ' ' || out[i - 1] == '\t')) {
            --i;
        }
    }
    out[i] = '\0';
    return i > 0;
}

static void
bridge_send_raw(int fd, const char *data, size_t len)
{
    if (fd < 0 || !data || len == 0) {
        return;
    }

    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, data + sent, len - sent, MSG_NOSIGNAL);
        if (n > 0) {
            sent += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
}

static void
bridge_send_line(int fd, const char *line)
{
    if (!line) {
        return;
    }
    bridge_send_raw(fd, line, strlen(line));
    bridge_send_raw(fd, "\n", 1);
}

static bool
bridge_window_mapped(const struct bridge_window *window)
{
    if (!window) {
        return false;
    }
    if (window->kind == BRIDGE_XDG) {
        return window->handle.xdg && window->handle.xdg->base &&
            window->handle.xdg->base->surface &&
            window->handle.xdg->base->surface->mapped;
    }
    return window->handle.xwayland && window->handle.xwayland->surface &&
        window->handle.xwayland->surface->mapped &&
        !window->handle.xwayland->override_redirect;
}

static const char *
bridge_window_title(const struct bridge_window *window)
{
    if (window->kind == BRIDGE_XDG) {
        return window->handle.xdg && window->handle.xdg->title ?
            window->handle.xdg->title : "";
    }
    return window->handle.xwayland && window->handle.xwayland->title ?
        window->handle.xwayland->title : "";
}

static const char *
bridge_window_app_id(const struct bridge_window *window)
{
    if (window->kind == BRIDGE_XDG) {
        return window->handle.xdg && window->handle.xdg->app_id ?
            window->handle.xdg->app_id : "";
    }
    return window->handle.xwayland && window->handle.xwayland->class ?
        window->handle.xwayland->class : "";
}

static void
bridge_write_window_json(FILE *f, const struct bridge_window *window)
{
    fprintf(f, "{\"id\":\"%" PRIu64 "\",\"type\":\"%s\",\"mapped\":%s,\"title\":",
        window->id,
        window->kind == BRIDGE_XDG ? "xdg" : "xwayland",
        bridge_window_mapped(window) ? "true" : "false");
    json_escape(f, bridge_window_title(window));
    fputs(",\"appId\":", f);
    json_escape(f, bridge_window_app_id(window));

    if (window->kind == BRIDGE_XWAYLAND && window->handle.xwayland) {
        const struct wlr_xwayland_surface *x = window->handle.xwayland;
        fprintf(f,
            ",\"x\":%d,\"y\":%d,\"width\":%u,\"height\":%u,"
            "\"minimized\":%s,\"maximized\":%s,\"fullscreen\":%s",
            x->x, x->y, x->width, x->height,
            x->minimized ? "true" : "false",
            (x->maximized_horz && x->maximized_vert) ? "true" : "false",
            x->fullscreen ? "true" : "false");
    } else if (window->kind == BRIDGE_XDG && window->handle.xdg &&
            window->handle.xdg->base) {
        const struct wlr_xdg_toplevel *x = window->handle.xdg;
        fprintf(f,
            ",\"width\":%d,\"height\":%d,\"maximized\":%s,\"fullscreen\":%s",
            x->base->geometry.width, x->base->geometry.height,
            x->current.maximized ? "true" : "false",
            x->current.fullscreen ? "true" : "false");
    }
    fputc('}', f);
}

static void
bridge_broadcast_window(const char *event, const struct bridge_window *window)
{
    if (!bridge_enabled || !event || !window) {
        return;
    }

    char *payload = NULL;
    size_t payload_len = 0;
    FILE *f = open_memstream(&payload, &payload_len);
    if (!f) {
        return;
    }
    fputs("{\"event\":", f);
    json_escape(f, event);
    fputs(",\"data\":", f);
    bridge_write_window_json(f, window);
    fputc('}', f);
    fclose(f);

    for (size_t i = 0; i < CYSHELL_LABWC_CLIENTS; ++i) {
        if (bridge_clients[i].fd >= 0 && bridge_clients[i].subscribed) {
            bridge_send_line(bridge_clients[i].fd, payload);
        }
    }
    free(payload);
}

static void
bridge_broadcast_removed(uint64_t id)
{
    char payload[160];
    snprintf(payload, sizeof(payload),
        "{\"event\":\"window.removed\",\"data\":{\"id\":\"%" PRIu64 "\"}}", id);
    for (size_t i = 0; i < CYSHELL_LABWC_CLIENTS; ++i) {
        if (bridge_clients[i].fd >= 0 && bridge_clients[i].subscribed) {
            bridge_send_line(bridge_clients[i].fd, payload);
        }
    }
}

static struct bridge_window *
bridge_find_window(uint64_t id)
{
    struct bridge_window *window;
    wl_list_for_each(window, &bridge_windows, link) {
        if (window->id == id) {
            return window;
        }
    }
    return NULL;
}

static void
bridge_window_detach_surface_listeners(struct bridge_window *window)
{
    listener_detach(&window->map);
    listener_detach(&window->unmap);
}

static void
bridge_window_free(struct bridge_window *window)
{
    if (!window) {
        return;
    }
    uint64_t id = window->id;
    listener_detach(&window->destroy);
    listener_detach(&window->map);
    listener_detach(&window->unmap);
    listener_detach(&window->set_title);
    listener_detach(&window->set_app_id_or_class);
    listener_detach(&window->associate);
    listener_detach(&window->dissociate);
    wl_list_remove(&window->link);
    bridge_broadcast_removed(id);
    free(window);
}

static void
handle_window_map(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, map);
    bridge_broadcast_window("window.changed", window);
}

static void
handle_window_unmap(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, unmap);
    bridge_broadcast_window("window.changed", window);
}

static void
handle_window_set_title(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, set_title);
    bridge_broadcast_window("window.changed", window);
}

static void
handle_window_set_app_id_or_class(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window =
        wl_container_of(listener, window, set_app_id_or_class);
    bridge_broadcast_window("window.changed", window);
}

static void
handle_window_destroy(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, destroy);
    bridge_window_free(window);
}

static void
bridge_attach_surface_listeners(struct bridge_window *window,
    struct wlr_surface *surface)
{
    if (!surface) {
        return;
    }
    bridge_window_detach_surface_listeners(window);
    wl_signal_add(&surface->events.map, &window->map);
    wl_signal_add(&surface->events.unmap, &window->unmap);
}

static void
handle_xwayland_associate(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, associate);
    if (window->handle.xwayland && window->handle.xwayland->surface) {
        bridge_attach_surface_listeners(window, window->handle.xwayland->surface);
    }
    bridge_broadcast_window("window.changed", window);
}

static void
handle_xwayland_dissociate(struct wl_listener *listener, void *data)
{
    (void)data;
    struct bridge_window *window = wl_container_of(listener, window, dissociate);
    bridge_window_detach_surface_listeners(window);
    bridge_broadcast_window("window.changed", window);
}

static struct bridge_window *
bridge_window_alloc(enum bridge_window_kind kind)
{
    struct bridge_window *window = calloc(1, sizeof(*window));
    if (!window) {
        return NULL;
    }
    window->id = bridge_next_window_id++;
    window->kind = kind;
    listener_init(&window->destroy);
    listener_init(&window->map);
    listener_init(&window->unmap);
    listener_init(&window->set_title);
    listener_init(&window->set_app_id_or_class);
    listener_init(&window->associate);
    listener_init(&window->dissociate);
    wl_list_insert(bridge_windows.prev, &window->link);
    return window;
}

static void
handle_new_xdg_toplevel(struct wl_listener *listener, void *data)
{
    (void)listener;
    if (!bridge_enabled || !data) {
        return;
    }
    struct wlr_xdg_toplevel *toplevel = data;
    struct bridge_window *window = bridge_window_alloc(BRIDGE_XDG);
    if (!window) {
        return;
    }
    window->handle.xdg = toplevel;

    window->destroy.notify = handle_window_destroy;
    window->set_title.notify = handle_window_set_title;
    window->set_app_id_or_class.notify = handle_window_set_app_id_or_class;
    window->map.notify = handle_window_map;
    window->unmap.notify = handle_window_unmap;

    wl_signal_add(&toplevel->events.destroy, &window->destroy);
    wl_signal_add(&toplevel->events.set_title, &window->set_title);
    wl_signal_add(&toplevel->events.set_app_id, &window->set_app_id_or_class);
    if (toplevel->base && toplevel->base->surface) {
        bridge_attach_surface_listeners(window, toplevel->base->surface);
    }
    bridge_broadcast_window("window.added", window);
}

static void
handle_new_xwayland_surface(struct wl_listener *listener, void *data)
{
    (void)listener;
    if (!bridge_enabled || !data) {
        return;
    }
    struct wlr_xwayland_surface *surface = data;
    struct bridge_window *window = bridge_window_alloc(BRIDGE_XWAYLAND);
    if (!window) {
        return;
    }
    window->handle.xwayland = surface;

    window->destroy.notify = handle_window_destroy;
    window->set_title.notify = handle_window_set_title;
    window->set_app_id_or_class.notify = handle_window_set_app_id_or_class;
    window->associate.notify = handle_xwayland_associate;
    window->dissociate.notify = handle_xwayland_dissociate;
    window->map.notify = handle_window_map;
    window->unmap.notify = handle_window_unmap;

    wl_signal_add(&surface->events.destroy, &window->destroy);
    wl_signal_add(&surface->events.set_title, &window->set_title);
    wl_signal_add(&surface->events.set_class, &window->set_app_id_or_class);
    wl_signal_add(&surface->events.associate, &window->associate);
    wl_signal_add(&surface->events.dissociate, &window->dissociate);
    if (surface->surface) {
        bridge_attach_surface_listeners(window, surface->surface);
    }
    bridge_broadcast_window("window.added", window);
}

static void
bridge_close_window(struct bridge_window *window)
{
    if (!window) {
        return;
    }
    if (window->kind == BRIDGE_XDG && window->handle.xdg) {
        wlr_xdg_toplevel_send_close(window->handle.xdg);
    } else if (window->kind == BRIDGE_XWAYLAND && window->handle.xwayland) {
        wlr_xwayland_surface_close(window->handle.xwayland);
    }
}

static void
bridge_reply_status(int fd)
{
    const char *labwc_version = getenv("CYSHELL_LABWC_VERSION");
    char *buf = NULL;
    size_t len = 0;
    FILE *f = open_memstream(&buf, &len);
    if (!f) {
        return;
    }
    fprintf(f,
        "{\"ok\":true,\"name\":\"CyShell LabWC Bridge\",\"api\":%d,"
        "\"inProcess\":true,\"pid\":%ld,\"labwcVersion\":",
        CYSHELL_LABWC_BRIDGE_API, (long)getpid());
    json_escape(f, labwc_version ? labwc_version : "");
    fprintf(f,
        ",\"wlrootsVersion\":\"%d.%d.%d\",\"socket\":",
        wlr_version_get_major(), wlr_version_get_minor(),
        wlr_version_get_micro());
    json_escape(f, bridge_socket_path);
    fputs(",\"capabilities\":[\"windows.list\",\"window.close\","
        "\"events.subscribe\",\"events.unsubscribe\",\"pointer.output\"]}", f);
    fclose(f);
    bridge_send_line(fd, buf);
    free(buf);
}

static void
bridge_reply_windows(int fd)
{
    char *buf = NULL;
    size_t len = 0;
    FILE *f = open_memstream(&buf, &len);
    if (!f) {
        return;
    }

    fputs("{\"ok\":true,\"windows\":[", f);
    bool first = true;
    struct bridge_window *window;
    wl_list_for_each(window, &bridge_windows, link) {
        if (!bridge_window_mapped(window)) {
            continue;
        }
        if (!first) {
            fputc(',', f);
        }
        first = false;
        bridge_write_window_json(f, window);
    }
    fputs("]}", f);
    fclose(f);

    bridge_send_line(fd, buf);
    free(buf);
}

static void
bridge_reply_pointer_output(int fd)
{
    const char *screen_name = "";
    double cursor_x = 0.0;
    double cursor_y = 0.0;
    struct bridge_cursor *state;

    wl_list_for_each_reverse(state, &bridge_cursors, link) {
        if (!state->cursor || !state->layout) {
            continue;
        }
        struct wlr_output *output = wlr_output_layout_output_at(
            state->layout, state->cursor->x, state->cursor->y);
        if (!output || !output->enabled || !output->name) {
            continue;
        }
        screen_name = output->name;
        cursor_x = state->cursor->x;
        cursor_y = state->cursor->y;
        break;
    }

    char *buf = NULL;
    size_t len = 0;
    FILE *f = open_memstream(&buf, &len);
    if (!f) {
        return;
    }
    fputs("{\"ok\":true,\"screen\":", f);
    json_escape(f, screen_name);
    if (*screen_name) {
        fprintf(f, ",\"x\":%.3f,\"y\":%.3f", cursor_x, cursor_y);
    }
    fputc('}', f);
    fclose(f);
    bridge_send_line(fd, buf);
    free(buf);
}

static void
bridge_handle_request(struct bridge_client *client, const char *request)
{
    char method[96] = {0};
    if (!json_get_value(request, "method", method, sizeof(method))) {
        bridge_send_line(client->fd,
            "{\"ok\":false,\"error\":\"method required\"}");
        return;
    }

    if (strcmp(method, "status") == 0 ||
            strcmp(method, "capabilities") == 0) {
        bridge_reply_status(client->fd);
        return;
    }

    if (strcmp(method, "windows.list") == 0) {
        bridge_reply_windows(client->fd);
        return;
    }

    if (strcmp(method, "pointer.output") == 0) {
        bridge_reply_pointer_output(client->fd);
        return;
    }

    if (strcmp(method, "events.subscribe") == 0) {
        client->subscribed = true;
        bridge_send_line(client->fd,
            "{\"ok\":true,\"subscribed\":true}");
        return;
    }

    if (strcmp(method, "events.unsubscribe") == 0) {
        client->subscribed = false;
        bridge_send_line(client->fd,
            "{\"ok\":true,\"subscribed\":false}");
        return;
    }

    if (strcmp(method, "window.close") == 0) {
        char idbuf[64] = {0};
        if (!json_get_value(request, "id", idbuf, sizeof(idbuf))) {
            bridge_send_line(client->fd,
                "{\"ok\":false,\"error\":\"id required\"}");
            return;
        }
        errno = 0;
        char *end = NULL;
        uint64_t id = strtoull(idbuf, &end, 10);
        if (errno || !end || *end != '\0' || id == 0) {
            bridge_send_line(client->fd,
                "{\"ok\":false,\"error\":\"invalid id\"}");
            return;
        }
        struct bridge_window *window = bridge_find_window(id);
        if (!window) {
            bridge_send_line(client->fd,
                "{\"ok\":false,\"error\":\"window not found\"}");
            return;
        }
        bridge_close_window(window);
        bridge_send_line(client->fd, "{\"ok\":true}");
        return;
    }

    bridge_send_line(client->fd,
        "{\"ok\":false,\"error\":\"unknown method\"}");
}

static void
bridge_client_close(struct bridge_client *client)
{
    if (!client || client->fd < 0) {
        return;
    }
    if (client->source) {
        wl_event_source_remove(client->source);
        client->source = NULL;
    }
    close(client->fd);
    client->fd = -1;
    client->used = 0;
    client->subscribed = false;
}

static int
bridge_client_ready(int fd, uint32_t mask, void *data)
{
    struct bridge_client *client = data;
    if (!client || fd < 0 ||
            (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR))) {
        bridge_client_close(client);
        return 0;
    }

    ssize_t n = read(fd, client->rx + client->used,
        sizeof(client->rx) - client->used - 1);
    if (n <= 0) {
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) {
            return 0;
        }
        bridge_client_close(client);
        return 0;
    }

    client->used += (size_t)n;
    client->rx[client->used] = '\0';

    char *start = client->rx;
    char *newline;
    while ((newline = strchr(start, '\n'))) {
        *newline = '\0';
        if (*start) {
            bridge_handle_request(client, start);
        }
        start = newline + 1;
    }

    size_t remaining = client->rx + client->used - start;
    memmove(client->rx, start, remaining);
    client->used = remaining;

    if (client->used == sizeof(client->rx) - 1) {
        bridge_send_line(client->fd,
            "{\"ok\":false,\"error\":\"request too large\"}");
        client->used = 0;
    }
    return 0;
}

static int
bridge_accept_ready(int fd, uint32_t mask, void *data)
{
    struct wl_display *display = data;
    if (!(mask & WL_EVENT_READABLE)) {
        return 0;
    }

    for (;;) {
        int client_fd = accept4(fd, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
        if (client_fd < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        struct bridge_client *slot = NULL;
        for (size_t i = 0; i < CYSHELL_LABWC_CLIENTS; ++i) {
            if (bridge_clients[i].fd < 0) {
                slot = &bridge_clients[i];
                break;
            }
        }
        if (!slot) {
            close(client_fd);
            continue;
        }

        slot->fd = client_fd;
        slot->used = 0;
        slot->subscribed = false;
        slot->source = wl_event_loop_add_fd(
            wl_display_get_event_loop(display),
            client_fd, WL_EVENT_READABLE, bridge_client_ready, slot);
        if (!slot->source) {
            close(client_fd);
            slot->fd = -1;
        }
    }
    return 0;
}

static bool
bridge_runtime_compatible(void)
{
    if (!bridge_candidate) {
        return false;
    }
    const char *labwc_version = getenv("CYSHELL_LABWC_VERSION");
    if (!labwc_version ||
            strcmp(labwc_version, CYSHELL_LABWC_SUPPORTED_VERSION) != 0) {
        bridge_log("disabled", "unsupported or unknown LabWC version");
        return false;
    }
    if (wlr_version_get_major() != CYSHELL_WLROOTS_ABI_MAJOR ||
            wlr_version_get_minor() != CYSHELL_WLROOTS_ABI_MINOR) {
        bridge_log("disabled", "unsupported wlroots ABI");
        return false;
    }
    return true;
}

static bool
bridge_socket_start(struct wl_display *display)
{
    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime || !*runtime) {
        bridge_log("disabled", "XDG_RUNTIME_DIR is unavailable");
        return false;
    }

    if (snprintf(bridge_socket_path, sizeof(bridge_socket_path),
            "%s/cyshell-labwc.sock", runtime) >=
            (int)sizeof(bridge_socket_path)) {
        bridge_log("disabled", "runtime socket path is too long");
        return false;
    }

    unlink(bridge_socket_path);

    bridge_listen_fd = socket(AF_UNIX,
        SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (bridge_listen_fd < 0) {
        bridge_log("error", "cannot create bridge socket");
        return false;
    }

    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path),
        "%s", bridge_socket_path);

    if (bind(bridge_listen_fd, (struct sockaddr *)&address,
            sizeof(address)) < 0 ||
            listen(bridge_listen_fd, CYSHELL_LABWC_CLIENTS) < 0) {
        char message[256];
        snprintf(message, sizeof(message), "socket setup failed: %s",
            strerror(errno));
        bridge_log("error", message);
        close(bridge_listen_fd);
        bridge_listen_fd = -1;
        unlink(bridge_socket_path);
        return false;
    }
    chmod(bridge_socket_path, 0600);

    struct wl_event_loop *loop = wl_display_get_event_loop(display);
    bridge_listen_source = wl_event_loop_add_fd(loop, bridge_listen_fd,
        WL_EVENT_READABLE, bridge_accept_ready, display);
    if (!bridge_listen_source) {
        bridge_log("error", "cannot attach bridge socket to LabWC event loop");
        close(bridge_listen_fd);
        bridge_listen_fd = -1;
        unlink(bridge_socket_path);
        return false;
    }

    char message[320];
    snprintf(message, sizeof(message),
        "active: API v%d at %s", CYSHELL_LABWC_BRIDGE_API,
        bridge_socket_path);
    bridge_log("ready", message);
    return true;
}

static void
bridge_socket_stop(void)
{
    for (size_t i = 0; i < CYSHELL_LABWC_CLIENTS; ++i) {
        bridge_client_close(&bridge_clients[i]);
    }
    if (bridge_listen_source) {
        wl_event_source_remove(bridge_listen_source);
        bridge_listen_source = NULL;
    }
    if (bridge_listen_fd >= 0) {
        close(bridge_listen_fd);
        bridge_listen_fd = -1;
    }
    if (bridge_socket_path[0]) {
        unlink(bridge_socket_path);
        bridge_socket_path[0] = '\0';
    }
}

__attribute__((constructor))
static void
bridge_constructor(void)
{
    wl_list_init(&bridge_windows);
    wl_list_init(&bridge_cursors);
    for (size_t i = 0; i < CYSHELL_LABWC_CLIENTS; ++i) {
        bridge_clients[i].fd = -1;
    }
    bridge_candidate = bridge_process_is_labwc();
    // Gate before either create hook can access wlroots structure layouts.
    bridge_candidate = bridge_runtime_compatible();
}

struct wlr_cursor *
wlr_cursor_create(void)
{
    typedef struct wlr_cursor *(*real_fn)(void);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_cursor_create");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_cursor_create");
        return NULL;
    }

    struct wlr_cursor *cursor = real();
    if (!bridge_candidate || !cursor) {
        return cursor;
    }

    struct bridge_cursor *state = calloc(1, sizeof(*state));
    if (!state) {
        bridge_log("warn", "cannot track LabWC cursor");
        return cursor;
    }
    state->cursor = cursor;
    wl_list_insert(bridge_cursors.prev, &state->link);
    return cursor;
}

void
wlr_cursor_attach_output_layout(struct wlr_cursor *cursor,
    struct wlr_output_layout *layout)
{
    typedef void (*real_fn)(struct wlr_cursor *, struct wlr_output_layout *);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_cursor_attach_output_layout");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_cursor_attach_output_layout");
        return;
    }

    real(cursor, layout);
    if (!bridge_candidate) {
        return;
    }

    struct bridge_cursor *state = bridge_find_cursor(cursor);
    if (state) {
        state->layout = layout;
    }
}

void
wlr_cursor_destroy(struct wlr_cursor *cursor)
{
    typedef void (*real_fn)(struct wlr_cursor *);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_cursor_destroy");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_cursor_destroy");
        return;
    }

    if (bridge_candidate) {
        struct bridge_cursor *state = bridge_find_cursor(cursor);
        if (state) {
            wl_list_remove(&state->link);
            free(state);
        }
    }
    real(cursor);
}

void
wlr_output_layout_destroy(struct wlr_output_layout *layout)
{
    typedef void (*real_fn)(struct wlr_output_layout *);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_output_layout_destroy");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_output_layout_destroy");
        return;
    }

    if (bridge_candidate) {
        bridge_forget_output_layout(layout);
    }
    real(layout);
}

void
wl_display_run(struct wl_display *display)
{
    typedef void (*real_fn)(struct wl_display *);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wl_display_run");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wl_display_run");
        return;
    }

    bridge_enabled = bridge_runtime_compatible();
    if (bridge_enabled && !bridge_socket_start(display)) {
        bridge_enabled = false;
    }

    real(display);

    bridge_enabled = false;
    bridge_socket_stop();
}

struct wlr_xdg_shell *
wlr_xdg_shell_create(struct wl_display *display, uint32_t version)
{
    typedef struct wlr_xdg_shell *(*real_fn)(
        struct wl_display *, uint32_t);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_xdg_shell_create");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_xdg_shell_create");
        return NULL;
    }

    struct wlr_xdg_shell *shell = real(display, version);
    if (bridge_candidate && shell && !bridge_xdg_hook) {
        bridge_xdg_hook = calloc(1, sizeof(*bridge_xdg_hook));
        if (bridge_xdg_hook) {
            listener_init(&bridge_xdg_hook->new_toplevel);
            bridge_xdg_hook->new_toplevel.notify = handle_new_xdg_toplevel;
            wl_signal_add(&shell->events.new_toplevel,
                &bridge_xdg_hook->new_toplevel);
        }
    }
    return shell;
}

struct wlr_xwayland *
wlr_xwayland_create(struct wl_display *display,
    struct wlr_compositor *compositor, bool lazy)
{
    typedef struct wlr_xwayland *(*real_fn)(
        struct wl_display *, struct wlr_compositor *, bool);
    static real_fn real;

    if (!real) {
        real = (real_fn)dlsym(RTLD_NEXT, "wlr_xwayland_create");
    }
    if (!real) {
        bridge_log("fatal", "cannot resolve wlr_xwayland_create");
        return NULL;
    }

    struct wlr_xwayland *xwayland = real(display, compositor, lazy);
    if (bridge_candidate && xwayland && !bridge_xwayland_hook) {
        bridge_xwayland_hook = calloc(1, sizeof(*bridge_xwayland_hook));
        if (bridge_xwayland_hook) {
            listener_init(&bridge_xwayland_hook->new_surface);
            bridge_xwayland_hook->new_surface.notify =
                handle_new_xwayland_surface;
            wl_signal_add(&xwayland->events.new_surface,
                &bridge_xwayland_hook->new_surface);
        }
    }
    return xwayland;
}
