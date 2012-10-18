/*
 * Provides Windows-specific implementations of some TestAgentd functions.
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
#include "platform.h"

char* get_script_path(void)
{
    static char path[MAX_PATH+11];
    if (!GetTempPathA(sizeof(path), path))
    {
        error("unable to retrieve the temporary directory path\n");
        exit(1);
    }
    strcat(path, "\\script.bat");
    return path;
}

static HANDLE child = NULL;
static DWORD child_pid;
static char* child_path;
void cleanup_child(void)
{
    if (child)
    {
        DeleteFile(child_path);
        free(child_path);
        child_path = NULL;

        CloseHandle(child);
        child = NULL;
        child_pid = 0;
    }
}

void start_child(SOCKET client, char* path)
{
    STARTUPINFO si;
    PROCESS_INFORMATION pi;

    child_path = path;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    if (CreateProcess(path, NULL, NULL, NULL, FALSE, NORMAL_PRIORITY_CLASS,
                       NULL, NULL, &si, &pi))
    {
        report_status(client, "ok: started process %u\n", pi.dwProcessId);
        child = pi.hProcess;
        child_pid = pi.dwProcessId;
        CloseHandle(pi.hThread);
    }
    else
    {
        report_status(client, "error: could not run '%s': %u\n", path, GetLastError());
    }
}

void wait_for_child(SOCKET client)
{
    HANDLE handles[2];
    DWORD r;

    handles[0] = WSACreateEvent();
    WSAEventSelect(client, handles[0], FD_CLOSE);
    handles[1] = child;
    while (child)
    {
        r = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
        switch (r)
        {
        case WAIT_OBJECT_0:
            report_status(client, "error: connection closed\n");
            CloseHandle(handles[0]);
            return;
        case WAIT_OBJECT_0 + 1:
            if (GetExitCodeProcess(child, &r))
            {
                report_status(client, "ok: process %u returned status %u\n", child_pid, r << 8);
                CloseHandle(handles[0]);
                cleanup_child();
                return;
            }
            break;
        default:
            debug("WaitForMultipleObjects() returned %u! Retrying...\n", r);
            break;
        }
    }
    CloseHandle(handles[0]);
    report_status(client, "error: no process to wait for\n");
}

int sockeintr(void)
{
    return WSAGetLastError() == WSAEINTR;
}

const char* sockerror(void)
{
    static char msg[1024];

    msg[0] = '\0';
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS  | FORMAT_MESSAGE_MAX_WIDTH_MASK,
                   NULL, WSAGetLastError(), LANG_USER_DEFAULT,
                   msg, sizeof(msg), NULL);
    msg[sizeof(msg)-1] = '\0';
    return msg;
}

char* sockaddr_to_string(struct sockaddr* sa, socklen_t len)
{
    /* Store the name in a buffer large enough for DNS hostnames */
    static char name[256+6];
    DWORD size = sizeof(name);
    /* This also appends the port number */
    if (WSAAddressToString(sa,len, NULL, name, &size))
        sprintf(name, "unknown host (family %d)", sa->sa_family);
    return name;
}

int (WINAPI *pgetaddrinfo)(const char *node, const char *service,
                           const struct addrinfo *hints,
                           struct addrinfo **addresses);
void (WINAPI *pfreeaddrinfo)(struct addrinfo *addresses);

int ta_getaddrinfo(const char *node, const char *service,
                   struct addrinfo **addresses)
{
    struct servent* sent;
    u_short port;
    char dummy;
    struct hostent* hent;
    char** addr;
    struct addrinfo *ai;
    struct sockaddr_in *sin4;
    struct sockaddr_in6 *sin6;

    if (pgetaddrinfo)
    {
        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_flags = AI_PASSIVE;
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        return pgetaddrinfo(node, service, &hints, addresses);
    }

    sent = getservbyname(service, "tcp");
    if (sent)
        port = sent->s_port;
    else if (!service)
        port = 0;
    else if (sscanf(service, "%hu%c", &port, &dummy) == 1)
        port = htons(port);
    else
        return EAI_SERVICE;

    *addresses = NULL;
    hent = gethostbyname(node);
    if (!hent)
        return EAI_NONAME;
    for (addr = hent->h_addr_list; *addr; addr++)
    {
        ai = malloc(sizeof(*ai));
        switch (hent->h_addrtype)
        {
        case AF_INET:
            ai->ai_addrlen = sizeof(*sin4);
            ai->ai_addr = malloc(ai->ai_addrlen);
            sin4 = (struct sockaddr_in*)ai->ai_addr;
            sin4->sin_family = hent->h_addrtype;
            sin4->sin_port = port;
            memcpy(&sin4->sin_addr, *addr, hent->h_length);
            break;
        case AF_INET6:
            ai->ai_addrlen = sizeof(*sin6);
            ai->ai_addr = malloc(ai->ai_addrlen);
            sin6 = (struct sockaddr_in6*)ai->ai_addr;
            sin6->sin6_family = hent->h_addrtype;
            sin4->sin_port = port;
            sin6->sin6_flowinfo = 0;
            memcpy(&sin6->sin6_addr, *addr, hent->h_length);
            break;
        default:
            debug("ignoring unknown address type %u\n", hent->h_addrtype);
            free(ai);
            continue;
        }
        ai->ai_flags = 0;
        ai->ai_family = hent->h_addrtype;
        ai->ai_socktype = SOCK_STREAM;
        ai->ai_protocol = IPPROTO_TCP;
        ai->ai_canonname = NULL; /* We don't use it anyway */
        ai->ai_next = *addresses;
        *addresses = ai;
    }
    if (!node)
    {
        /* Add INADDR_ANY last so it is tried first */
        ai = malloc(sizeof(*ai));
        ai->ai_addrlen = sizeof(*sin4);
        ai->ai_addr = malloc(ai->ai_addrlen);
        sin4 = (struct sockaddr_in*)ai->ai_addr;
        sin4->sin_family = ai->ai_family = AF_INET;
        sin4->sin_port = port;
        sin4->sin_addr.S_un.S_addr = INADDR_ANY;
        ai->ai_flags = 0;
        ai->ai_socktype = SOCK_STREAM;
        ai->ai_protocol = IPPROTO_TCP;
        ai->ai_canonname = NULL; /* We don't use it anyway */
        ai->ai_next = *addresses;
        *addresses = ai;
    }
    return 0;
}

void ta_freeaddrinfo(struct addrinfo *addresses)
{
    if (pfreeaddrinfo)
        pfreeaddrinfo(addresses);
    else
    {
        while (addresses)
        {
            free(addresses->ai_addr);
            addresses = addresses->ai_next;
        }
    }
}

int init_platform(void)
{
    HMODULE hdll;
    WORD wVersionRequested;
    WSADATA wsaData;
    int rc;

    wVersionRequested = MAKEWORD(2, 2);
    rc = WSAStartup(wVersionRequested, &wsaData);
    if (rc)
    {
        error("unable to initialize winsock (%d)\n", rc);
        return 0;
    }

    hdll = GetModuleHandle("ws2_32");
    pgetaddrinfo = (void*)GetProcAddress(hdll, "getaddrinfo");
    pfreeaddrinfo = (void*)GetProcAddress(hdll, "freeaddrinfo");
    return 1;
}
