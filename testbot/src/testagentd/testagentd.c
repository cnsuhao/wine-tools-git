/*
 * Provides a simple way to send/receive files and to run scripts.
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
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "platform.h"

#define CHUNK_SIZE 4096

const char *name0;
int opt_debug = 0;


void error(const char* format, ...)
{
    va_list valist;
    fprintf(stderr, "%s:error: ", name0);
    va_start(valist, format);
    vfprintf(stderr, format, valist);
    va_end(valist);
}

void debug(const char* format, ...)
{
    if (opt_debug)
    {
        va_list valist;
        va_start(valist, format);
        vfprintf(stderr, format, valist);
        va_end(valist);
    }
}

static char buffer[CHUNK_SIZE];
static int buf_pos, buf_size;

static void reset_buffer(void)
{
    buf_pos = buf_size = 0;
}

static int fill_buffer(SOCKET sock)
{
    int n;

    if (buf_pos == buf_size)
    {
        /* Everything has been read, empty the buffer */
        buf_pos = buf_size = 0;
    }
    if (buf_size == sizeof(buffer))
    {
        /* The buffer is full */
        return 0;
    }

    n = recv(sock, buffer + buf_size, sizeof(buffer) - buf_size, 0);
    if (n > 0)
        buf_size += n;
    return n;
}

static char* _get_string(void)
{
    char *str, *e;
    char *eod = buffer + buf_size;
    str = e = buffer + buf_pos;
    while (e < eod)
    {
        if (*e == '\n')
        {
            *e = '\0';
            buf_pos = e + 1 - buffer;
            return str;
        }
        e++;
    }
    return NULL;
}

/* Only strings smaller than the buffer size are supported */
static char* get_string(SOCKET sock)
{
    char* str;

    if (buf_pos == buf_size)
        fill_buffer(sock);
    str = _get_string();
    if (str || buf_pos == 0)
        return str;

    /* Try to grab some more data */
    memcpy(buffer, buffer + buf_pos, buf_size - buf_pos);
    buf_size -= buf_pos;
    buf_pos = 0;
    fill_buffer(sock);

    return _get_string();
}

static char* get_data(SOCKET sock, int *len)
{
    char* data;
    if (buf_pos == buf_size)
    {
        *len = fill_buffer(sock);
        if (*len <= 0)
            return NULL;
    }
    else
        *len = buf_size - buf_pos;
    data = buffer + buf_pos;
    buf_pos = buf_size;
    return data;
}

static const char* stream_from_net(SOCKET src, int dst)
{
    char buffer[CHUNK_SIZE];
    while (1)
    {
        int r, w;
        r = recv(src, buffer, sizeof(buffer), 0);
        if (r == 0) /* EOF */
            return NULL;
        if (r < 0)
            return sockerror();
        w = write(dst, buffer, r);
        if (w != r)
        {
            error("could only write %d bytes out of %d: %s\n", w, r, strerror(errno));
            return strerror(errno);
        }
    }
    return NULL;
}

/* This cannot be merged with stream_from_net() because on Windows
 * read()/write() cannot operate on sockets and recv()/send() cannot operate
 * on file descriptors :-(
 */
static const char* stream_to_net(int src, SOCKET dst)
{
    char buffer[CHUNK_SIZE];
    while (1)
    {
        int r, w;
        r = read(src, buffer, sizeof(buffer));
        if (r == 0) /* EOF */
            return NULL;
        if (r < 0)
            return strerror(errno);
        w = send(dst, buffer, r, 0);
        if (w != r)
        {
            error("could only send %d bytes out of %d: %s\n", w, r, sockerror());
            return sockerror();
        }
    }
    return NULL;
}

static char* status = NULL;
static unsigned status_size = 0;
static void vset_status(const char* format, va_list valist)
{
    int len;
    va_list args;
    len = 0;
    do
    {
        if (len >= status_size)
        {
            /* len does not count the trailing '\0'. So add 1 and round up
             * to the next 16 bytes multiple.
             */
            status_size = (len + 1 + 0xf) & ~0xf;
            status = realloc(status, status_size);
        }
        va_copy(args, valist);
        len = vsnprintf(status, status_size, format, args);
        va_end(args);
        if (len < 0)
            len = status_size * 1.1;
    }
    while (len >= status_size);
    if (opt_debug || strncmp(status, "ok:", 3) != 0)
        fprintf(stderr, "%s", status);
}

static void set_status(const char* format, ...)
{
    va_list valist;
    va_start(valist, format);
    vset_status(format, valist);
    va_end(valist);
}

void report_status(SOCKET client, const char* format, ...)
{
    va_list valist;
    shutdown(client, SHUT_RD);
    va_start(valist, format);
    vset_status(format, valist);
    va_end(valist);
    send(client, status, strlen(status), 0);
}

static void process_command(SOCKET client)
{
    char *command;
    const char* err;

    reset_buffer();
    command = get_string(client);
    debug("Processing command %s\n", command ? command : "(null)");
    if (!command)
    {
        report_status(client, "error: could not read the command\n");
    }
    else if (strcmp(command, "read") == 0)
    {
        /* Read the specified file */
        char* filename;
        int fd;
        struct stat st;
        char str[80];

        filename = get_string(client);
        if (!filename)
        {
            report_status(client, "error: missing filename parameter for read\n");
            return;
        }
        debug("read '%s'\n", filename);
        fd = open(filename, O_RDONLY | O_BINARY);
        if (fd < 0)
        {
            report_status(client, "error: unable to open '%s' for reading: %s\n", filename, strerror(errno));
            return;
        }
        if (fstat(fd, &st))
            st.st_size = -1;
        sprintf(str, "ok: size=%ld\n", st.st_size);
        send(client, str, strlen(str), 0);
        err = stream_to_net(fd, client);
        close(fd);
        if (err)
        {
            /* We cannot report the error now because it would get mixed
             * with the file data
             */
            set_status("error: an error occurred while reading '%s': %s\n", filename, err);
            return;
        }
        set_status("ok: read done\n");
    }
    else if (strcmp(command, "write") == 0)
    {
        /* Write to the specified file */
        char* filename;
        int fd;
        char* data;
        int len;

        filename = get_string(client);
        if (!filename)
        {
            report_status(client, "error: missing filename parameter for write\n");
            return;
        }
        debug("write '%s'\n", filename);
        fd = open(filename, O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, 0600);
        if (fd < 0)
        {
            report_status(client, "error: unable to open '%s' for writing: %s\n", filename, strerror(errno));
            unlink(filename);
            return;
        }
        data = get_data(client, &len);
        if (data && write(fd, data, len) != len)
        {
            report_status(client, "error: an error occurred while writing to '%s': %s\n", filename, strerror(errno));
            close(fd);
            unlink(filename);
            return;
        }
        err = stream_from_net(client, fd);
        close(fd);
        if (err)
        {
            report_status(client, "error: an error occurred while writing to '%s': %s\n", filename, err);
            unlink(filename);
            return;
        }
        else
            report_status(client, "ok: write done\n");
    }
    else if (strcmp(command, "runscript") == 0)
    {
        /* Run the specified script */
        int fd, len;
        char *data, *script;

        cleanup_child();
        script = get_script_path();
        debug("runscript '%s'\n", script);
        fd = open(script, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0)
        {
            report_status(client, "error: unable to open '%s' for writing: %s\n", script, strerror(errno));
            free(script);
            return;
        }
        data = get_data(client, &len);
#ifndef WIN32
        /* Use the standard shell if none is specified */
        if (data && strncmp(data, "#!/", 3) && strncmp(data, "# !/", 4))
        {
            const char shell[]="#!/bin/sh\n";
            write(fd, shell, sizeof(shell));
        }
#endif
        if (data && write(fd, data, len) != len)
        {
            report_status(client, "error: an error occurred while writing to '%s': %s\n", script, strerror(errno));
            close(fd);
            unlink(script);
            free(script);
            return;
        }
        err = stream_from_net(client, fd);
        close(fd);
        if (err)
        {
            report_status(client, "error: an error occurred while saving the script to '%s': %s\n", script, err);
            unlink(script);
            free(script);
            return;
        }
        start_child(client, script);
    }
    else if (strcmp(command, "waitchild") == 0)
    {
        /* Wait for the last process we started */
        wait_for_child(client);
    }
    else if (strcmp(command, "status") == 0)
    {
        /* Return the status of the previous command */
        shutdown(client, SHUT_RD);
        send(client, status, strlen(status), 0);
    }
    else
    {
        report_status(client, "error: unknown command: %s\n", command);
    }
}

void* sockaddr_getaddr(struct sockaddr* sa, socklen_t* len)
{
    switch (sa->sa_family)
    {
    case AF_INET:
        if (len)
            *len = sizeof(struct in_addr);
        return &((struct sockaddr_in*)sa)->sin_addr;
    case AF_INET6:
        if (len)
            *len = sizeof(struct in6_addr);
        return &((struct sockaddr_in6*)sa)->sin6_addr;
    }
    if (len)
        *len = 0;
    return NULL;
}

static int sockaddr_equal(struct sockaddr* sa1, struct sockaddr* sa2)
{
    void *addr1, *addr2;
    socklen_t len;

    if (sa1->sa_family != sa2->sa_family)
        return 0;

    addr1 = sockaddr_getaddr(sa1, &len);
    addr2 = sockaddr_getaddr(sa2, &len);
    if (!addr1 || !addr2)
        return 0;
    return memcmp(addr1, addr2, len) == 0;
}

static int is_host_allowed(SOCKET client, const char* srchost, int addrlen)
{
    struct addrinfo *addresses, *addrp;
    struct sockaddr *peeraddr;
    socklen_t peerlen;
    int rc;

    if (!srchost)
        return 1;

    peerlen = addrlen;
    peeraddr = malloc(peerlen);
    if (getpeername(client, peeraddr, &peerlen))
    {
        error("unable to get the peer address: %s\n", sockerror());
        free(peeraddr);
        return 0;
    }
    debug("Received connection from %s\n", sockaddr_to_string(peeraddr, peerlen));
    rc = ta_getaddrinfo(srchost, NULL, &addresses);
    if (rc)
    {
        error("unable to resolve '%s': %s\n", srchost, gai_strerror(rc));
        free(peeraddr);
        return 0;
    }

    addrp = addresses;
    do
    {
        debug("  checking against %s\n", sockaddr_to_string(addrp->ai_addr, addrp->ai_addrlen));
        if (sockaddr_equal(peeraddr, addrp->ai_addr))
        {
            free(peeraddr);
            ta_freeaddrinfo(addresses);
            return 1;
        }
    }
    while ((addrp = addrp->ai_next) != NULL);
    ta_freeaddrinfo(addresses);

    debug("  -> rejecting connection\n");
    free(peeraddr);
    return 0;
}

int main(int argc, char** argv)
{
    const char* p;
    char** arg;
    char* opt_port = NULL;
    char* opt_srchost = NULL;
    struct addrinfo *addresses, *addrp;
    int rc, addrlen;
    int opt_usage = 0;
    SOCKET master;
    int on = 1;

    name0 = p = argv[0];
    while (*p != '\0')
    {
        if (*p == '/' || *p == '\\')
            name0 = p + 1;
        p++;
    }

    arg = argv + 1;
    while (*arg)
    {
        if (strcmp(*arg, "--debug") == 0)
        {
            opt_debug = 1;
        }
        else if (strcmp(*arg, "--help") == 0)
        {
            opt_usage = 1;
        }
        else if (**arg == '-')
        {
            error("unknown option '%s'\n", *arg);
            opt_usage = 2;
            break;
        }
        else if (opt_port == NULL)
        {
            opt_port = *arg;
        }
        else if (opt_srchost == NULL)
        {
            opt_srchost = *arg;
        }
        else
        {
            error("unexpected option '%s'\n", *arg);
            opt_usage = 2;
            break;
        }
        arg++;
    }
    if (!opt_usage)
    {
        if (!opt_port)
        {
            error("you must specify the port to listen on\n");
            opt_usage = 2;
        }

        if (!init_platform())
        {
            if (!opt_usage)
                exit(1);
            /* else opt_usage will force us to exit early anyway */
        }
        else if (opt_srchost)
        {
            /* Verify that the specified source host is valid */
            rc = ta_getaddrinfo(opt_srchost, NULL, &addresses);
            if (rc)
            {
                error("unable to resolve '%s': %s\n", opt_srchost, gai_strerror(rc));
                opt_usage = 2;
            }
            else
            {
                if (opt_debug)
                {
                    addrp = addresses;
                    do
                    {
                        debug("Accepting connections from %s\n", sockaddr_to_string(addrp->ai_addr, addrp->ai_addrlen));
                    }
                    while ((addrp = addrp->ai_next) != NULL);
                }
                ta_freeaddrinfo(addresses);
            }
        }
    }
    if (opt_usage == 2)
    {
        error("try '%s --help' for more information\n", name0);
        exit(2);
    }
    if (opt_usage)
    {
        printf("Usage: %s [--debug] [--help] PORT [SRCHOST]\n", name0);
        printf("\n");
        printf("Provides a simple way to send/receive files and to run scripts on this host.\n");
        printf("\n");
        printf("Where:\n");
        printf("  PORT     The port to listen on for connections.\n");
        printf("  SRCHOST  If specified, only connections from this host will be accepted.\n");
        printf("  --debug  Prints detailed information about what happens.\n");
        printf("  --help   Shows this usage message.\n");
        exit(0);
    }

    /* Bind to the host in a protocol neutral way */
    rc = ta_getaddrinfo(NULL, opt_port, &addresses);
    if (rc)
    {
        error("unable to get the host address for port %s: %s\n", opt_port, gai_strerror(rc));
        exit(1);
    }
    for (addrp = addresses; addrp; addrp = addrp->ai_next)
    {
        if (addrp->ai_family != PF_INET)
            continue;
        master = socket(addrp->ai_family, addrp->ai_socktype, addrp->ai_protocol);
        if (master < 0)
            continue;
        setsockopt(master, SOL_SOCKET, SO_REUSEADDR, (void*)&on, sizeof(on));

        debug("Trying to bind to %s\n", sockaddr_to_string(addrp->ai_addr, addrp->ai_addrlen));
        if (bind(master, addrp->ai_addr, addrp->ai_addrlen) == 0)
            break;
        closesocket(master);
    };
    addrlen = addrp->ai_addrlen;
    ta_freeaddrinfo(addresses);
    if (addrp == NULL)
    {
        error("unable to bind the server socket: %s\n", sockerror());
        exit(1);
    }

    if (listen(master, 1) < 0)
    {
        error("listen() failed: %s\n", sockerror());
        exit(1);
    }
    set_status("ok: ready\n");

    while (1)
    {
        SOCKET client;
        debug("Waiting in accept()\n");
        client = accept(master, NULL, NULL);
        if (client >= 0)
        {
            if (is_host_allowed(client, opt_srchost, addrlen))
                process_command(client);
            closesocket(client);
        }
        else if (!sockeintr())
        {
            error("accept() failed: %s\n", sockerror());
            exit(1);
        }
    }

    cleanup_child();
    return 0;
}
