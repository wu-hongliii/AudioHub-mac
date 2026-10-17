// AudioHub macOS bridge. GPL-2.0-or-later.
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <pthread.h>
#include <errno.h>

static int transfer(int fd, void *buffer, size_t length, int writing) {
    char *p = buffer;
    while (length) {
        ssize_t n = writing ? write(fd, p, length) : read(fd, p, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        p += n; length -= (size_t)n;
    }
    return 1;
}

static void relay(int from, int to) {
    for (;;) {
        uint32_t length;
        if (!transfer(from, &length, 4, 0) || !length || length > 1048576) break;
        char *payload = malloc(length);
        if (!payload) break;
        int ok = transfer(from, payload, length, 0) && transfer(to, &length, 4, 1) && transfer(to, payload, length, 1);
        free(payload);
        if (!ok) break;
    }
}

static void *input(void *arg) {
    int fd = *(int *)arg;
    relay(STDIN_FILENO, fd);
    shutdown(fd, SHUT_RDWR);
    return NULL;
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "/tmp/audiohub-%u/bridge.sock", getuid());
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        fprintf(stderr, "AudioHub is not running.\n");
        if (fd >= 0) close(fd);
        return 1;
    }
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) || uid != getuid()) { close(fd); return 1; }
    pthread_t thread;
    if (pthread_create(&thread, NULL, input, &fd)) { close(fd); return 1; }
    relay(fd, STDOUT_FILENO);
    shutdown(fd, SHUT_RDWR);
    close(fd);
    // Returning terminates the stdin thread even if the browser has not closed stdin.
    return 0;
}
