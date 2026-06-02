#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/capability.h>
#include <sys/prctl.h>
#include <unistd.h>

static void die(const char *msg) {
  perror(msg);
  exit(1);
}

/* bwrap refuses to run with inherited file caps when not setuid. */
static void drop_capabilities(void) {
  cap_t caps = cap_init();
  if (caps == NULL) {
    die("cap_init");
  }
  if (cap_set_proc(caps) < 0) {
    die("cap_set_proc");
  }
  cap_free(caps);

  for (int cap = 0;; cap++) {
    if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_LOWER, cap, 0, 0) < 0) {
      if (errno == EINVAL) {
        break;
      }
      die("prctl PR_CAP_AMBIENT");
    }
  }
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <netns-name> <command> [args...]\n", argv[0]);
    return 2;
  }

  const char *nsname = argv[1];
  char path[256];
  int n = snprintf(path, sizeof(path), "/run/netns/%s", nsname);
  if (n < 0 || (size_t)n >= sizeof(path)) {
    fprintf(stderr, "netns name too long\n");
    return 1;
  }

  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
      die("open netns");
  }

  if (setns(fd, CLONE_NEWNET) < 0) {
    if (errno == EPERM) {
        fputs("setns: need CAP_SYS_ADMIN on agent-sandbox-enter (rebuild NixOS)\n", stderr);
    }
    die("setns");
  }
  close(fd);

  drop_capabilities();

  execvp(argv[2], argv + 2);
  die("execvp");
}
