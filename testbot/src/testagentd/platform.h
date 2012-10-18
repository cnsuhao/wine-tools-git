/*
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
#ifdef WIN32
# include <ws2tcpip.h>
# include <windows.h>

# ifndef SHUT_RD
#  define SHUT_RD SD_RECEIVE
# endif
#else
# include <arpa/inet.h>
# include <sys/types.h>
# include <sys/socket.h>
# include <sys/select.h>
# include <netdb.h>

/*
 * Platform-specific functions.
 */

typedef int SOCKET;
# define closesocket(sock) close((sock))
#endif

#ifndef O_BINARY
# define O_BINARY 0
#endif


int init_platform(void);
char* get_script_path(void);

/* Starts the specified command in the background and reports the status to
 * the client.
 */
void start_child(SOCKET client, char* path);

/* If a command was started in the background, waits until either that command
 * terminates or the client disconnects (typically because it got tired of
 * waiting).
 * If no command was started in the background, then reports an error
 * immediately.
 */
void wait_for_child(SOCKET client);

/* Releases the resources used for tracking the last command. */
void cleanup_child(void);

/* Returns a string describing the last socket-related error */
int sockeintr(void);
const char* sockerror(void);

/* Converts a socket address into a string stored in a static buffer. */
char* sockaddr_to_string(struct sockaddr* sa, socklen_t len);

int ta_getaddrinfo(const char *node, const char *service,
                   struct addrinfo **addresses);

void ta_freeaddrinfo(struct addrinfo *addresses);


/*
 * testagentd functions
 */

void error(const char* format, ...);
void debug(const char* format, ...);
void report_status(SOCKET client, const char* format, ...);

void* sockaddr_getaddr(struct sockaddr* sa, socklen_t* len);
