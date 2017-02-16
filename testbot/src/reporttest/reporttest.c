/*
 * Copyright 2017 Francois Gouget
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
//#include <unistd.h>

#include <windows.h>

static void* extract_rcdata(LPCSTR name, LPCSTR type, DWORD* size)
{
    HRSRC rsrc;
    HGLOBAL hdl;
    LPVOID addr;

    if (!(rsrc = FindResourceA(NULL, name, type)) ||
        !(*size = SizeofResource(0, rsrc)) ||
        !(hdl = LoadResource(0, rsrc)) ||
        !(addr = LockResource(hdl)))
        return NULL;
    return addr;
}

static void usage(void)
{
    fprintf(stderr,
            "Usage: reporttest [-c COMMITID] [-t TAG] [--help]\n"
            "\n"
            "Generates a WineTest-style report containing test cases for tools that\n"
            "parse and verify them such as the TestBot and test.winehq.org scripts.\n"
            "\n"
            "  -C COMMITID Reports the results for this Git commit id.\n"
            "  -t TAG      Reports the results for this tag.\n"
            "  --help      Print this message and exit.\n"
            "Other WineTest options are either ignored or not supported.\n"
            );
}

int main(int argc, char** argv)
{
    char *commitid = NULL, *email = NULL, *logname = NULL, *tag = NULL;
    int i;
    FILE *logfile;
    char *report, *eol;
    char line[1024];
    DWORD l, size;

    for (i = 1; i < argc && argv[i]; i++)
    {
        if (strcmp(argv[i], "--help") == 0)
        {
            usage();
            return 0;
        }
        else if (!strcmp(argv[i], "--version"))
        {
            printf("unknown\n");
            return 0;
        }
        else if (argv[i][0] != '-' && argv[i][0] != '/')
        {
            fprintf(stderr, "error: Outputting the lines of a specific test (%s) is not supported.\n", argv[i]);
            /* This would require adjusting the report template to use the real
             * process pid. Plus some tests imply mixing the output of unit
             * tests which would not make sense.
             */
            return 2;
        }
        else if (strlen(argv[i]) > 2)
        {
            fprintf(stderr, "error: Unknown option '%s'\n", argv[i]);
            return 2;
        }
        else switch (argv[i][1])
        {
        case 'c':
        case 'e':
        case 'n':
        case 'p':
        case 'q':
        case 's':
            /* Ignore unsupported options */
            break;
        case 'd':
        case 'i':
        case 'S':
        case 'u':
            /* Ignore unsupported options */
            if (!argv[++i])
            {
                usage();
                return 2;
            }
            break;
        case 'C':
            if (commitid)
            {
                fprintf(stderr, "error: Only one commit id can be specified (was %s)\n", commitid);
                return 2;
            }
            if (!(commitid = argv[++i]))
            {
                fprintf(stderr, "error: Missing commit id value\n");
                usage();
                return 2;
            }
            break;
        case 'm':
            if (email)
            {
                fprintf(stderr, "error: Only one email can be specified (was %s)\n", email);
                return 2;
            }
            if (!(email = argv[++i]))
            {
                fprintf(stderr, "error: Missing email value\n");
                usage();
                return 2;
            }
            break;
        case 'o':
            if (logname)
            {
                fprintf(stderr, "error: Only one report file name can be specified (was %s)\n", logname);
                return 2;
            }
            if (!(logname = argv[++i]))
            {
                usage();
                return 2;
            }
            break;
        case 't':
            if (tag)
            {
                fprintf(stderr, "error: Only one tag can be specified (was %s)\n", tag);
                return 2;
            }
            if (!(tag = argv[++i]))
            {
                fprintf(stderr, "error: Missing tag value\n");
                usage();
                return 2;
            }
            break;
        case 'x':
            /* Nothing to do */
            return 0;
        case 'h':
        case '?':
            usage();
            return 0;
        default:
            fprintf(stderr, "error: Unknown option: %s\n", argv[i]);
            usage();
            return 2;
        }
    }

    report = extract_rcdata("TESTREPORT", "TESTRES", &size);
    if (!report)
    {
        fprintf(stderr, "error: Could not extract the test report (%lu)\n", GetLastError());
        return 1;
    }

    if (logname)
    {
        logfile = fopen(logname, "w");
        if (!logfile)
        {
            fprintf(stderr, "error: Could not open '%s' for writing the test: %s\n", logname, strerror(errno));
            return 1;
        }
    }
    else
        logfile = stdout;

    l = 0;
    while (size)
    {
        /* The report is not '\0' terminated and may not have a trailing '\n' */
        char last = '\0';
        eol = report;
        while (size && last != '\n')
        {
            last = *eol;
            eol++;
            size--;
        }
        l++;
        if (eol-report+1 > sizeof(line))
        {
            fprintf(stderr, "error: line %lu is too long!\n", l);
            return 1;
        }
        memcpy(line, report, eol-report);
        line[eol-report] = '\0';
        report = eol;

        /* Empty lines are only there to make the report more editable */
        if (*line == '\n') continue;

        if (commitid && strncmp(line, "Tests from build ", 17) == 0)
        {
            fprintf(logfile, "Tests from build %s\n", commitid);
        }
        else if (email && strncmp(line, "    Submitter=", 14) == 0)
        {
            fprintf(logfile, "    Submitter=%s\n", email);
        }
        else if (tag && strncmp(line, "Tag: ", 5) == 0)
        {
            fprintf(logfile, "Tag: %s\n", tag);
        }
        else if (strncmp(line, "stub ", 5) == 0)
        {
            char* unit = strchr(line, ':');
            if (!unit)
            {
                fprintf(stderr, "error: The line below does not have a unit!\n");
                fputs(line, stdout);
                return 1;
            }
            unit++;
            line[strlen(line)-1] = '\0';
            fprintf(logfile, "%s start fake/source/%s.c -\n", line+5, unit);
            fprintf(logfile, "----- A standard successful unit test\n");
            fprintf(logfile, "----- Expected assessement: Success\n");
            fprintf(logfile, "1234:%s: 2 tests executed (0 marked as todo, 0 failures), 0 skipped.\n", unit);
            fprintf(logfile, "%s:1234 done (0) in 0s\n", line+5);
        }
        else
        {
            fputs(line, logfile);
        }
    }
    if (logfile != stdout)
        fclose(logfile);
    return 0;
}
