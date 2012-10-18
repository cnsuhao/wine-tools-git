/*
 * Provides Unix-specific implementations of some TestAgentd functions.
 *
 * Copyright 2012 Francois Gouget
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include "platform.h"

# define WINEBOTDIR  "/home/winehq/tools/testbot/var/staging"


char* get_script_path(void)
{
    struct stat st;
    char *dir, *script;

    if (stat(WINEBOTDIR, &st) == 0 && S_ISDIR(st.st_mode) &&
        access(WINEBOTDIR, W_OK) == 0)
        dir = WINEBOTDIR;
    else if (getenv("TMPDIR"))
        dir = getenv("TMPDIR");
    else
        dir = "/tmp";
    script = malloc(strlen(dir)+7+1);
    sprintf(script, "%s/script", dir);
    return script;
}

static pid_t child = 0;
static char* child_path;
static pid_t reaped = 0;
static int reaped_status;
void cleanup_child(void)
{
    if (child_path)
    {
        unlink(child_path);
        free(child_path);
        child_path = NULL;
    }
    child = 0;
}

void reaper(int signum)
{
    pid_t pid;
    int status;

    pid = wait(&status);
    debug("process %u returned %d\n", (unsigned)pid, status);
    if (pid == child)
    {
        cleanup_child();
        reaped_status = status;
        reaped = pid;
    }
}

void start_child(SOCKET client, char* path)
{
    pid_t pid;

    chmod(path, 0700);
    child_path = path;
    child = pid = fork();
    if (pid == 0)
    {
        char* argv[2];
        argv[0] = path;
        argv[1] = NULL;
        execve(path, argv, NULL);
        error("could not run '%s': %s\n", strerror(errno));
        exit(1);
    }
    if (pid < 0)
    {
        cleanup_child();
        report_status(client, "error: could not fork: %s\n", strerror(errno));
        return;
    }
    report_status(client, "ok: started process %d\n", pid);
}

void wait_for_child(SOCKET client)
{
    while (child)
    {
        fd_set rfds;
        char buf;

        /* select() blocks until either the client disconnects or until, or
         * the SIGCHLD signal indicates the child has exited. The recv() call
         * tells us if it is the former.
         */
        FD_ZERO(&rfds);
        FD_SET(client, &rfds);
        if (select(client+1, &rfds, NULL, NULL, NULL) == 1 &&
            FD_ISSET(client, &rfds) &&
            recv(client, &buf, 1, MSG_PEEK | MSG_DONTWAIT) <= 0)
        {
            report_status(client, "error: connection closed\n");
            return;
        }
    }
    if (reaped)
        report_status(client, "ok: process %d returned status %d\n", reaped, reaped_status);
    else
        report_status(client, "error: no process to wait for\n");
}

int sockeintr(void)
{
    return errno == EINTR;
}

const char* sockerror(void)
{
    return strerror(errno);
}

char* sockaddr_to_string(struct sockaddr* sa, socklen_t len)
{
    /* Store the name in a buffer large enough for DNS hostnames */
    static char name[256+6];
    void* addr;
    u_short port;

    addr = sockaddr_getaddr(sa, NULL);
    if (!addr || !inet_ntop(sa->sa_family, addr, name, sizeof(name)))
    {
        sprintf(name, "unknown host (family %d)", sa->sa_family);
        return NULL;
    }
    switch (sa->sa_family)
    {
    case AF_INET:
        port = htons(((struct sockaddr_in*)sa)->sin_port);
        break;
    case AF_INET6:
        port = htons(((struct sockaddr_in6*)sa)->sin6_port);
        break;
    default:
        port = 0;
    }
    if (port)
    {
        snprintf(name+strlen(name), sizeof(name)-strlen(name), ":%hu", port);
        name[sizeof(name)-1] = '\0';
    }
    return name;
}

int ta_getaddrinfo(const char *node, const char *service,
                   struct addrinfo **addresses)
{
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_flags = AI_PASSIVE;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    return getaddrinfo(node, service, &hints, addresses);
}

void ta_freeaddrinfo(struct addrinfo *addresses)
{
    return freeaddrinfo(addresses);
}

int init_platform(void)
{
    struct sigaction sa, osa;
    sa.sa_handler = reaper;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    if (sigaction(SIGCHLD, &sa, &osa) < 0)
    {
        error("could not set up the SIGCHLD handler: %s\n", strerror(errno));
        return 0;
    }
    return 1;
}
