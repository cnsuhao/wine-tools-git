/*
 * Verifies that the dlls needed for the test are present.
 *
 * Copyright 2009 Ge van Geldorp
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
#include <windows.h>

#define countof(Array) (sizeof(Array) / sizeof(Array[0]))

static unsigned Failures = 0;
static unsigned Skips = 0;
static char TestName[_MAX_PATH];


#define ReportError (_SetErrorLocation(__FILE__, __LINE__), 0) ? (void)0 : _ReportError

static const char *LocationFile;
static unsigned LocationLine;
static void _SetErrorLocation(const char* file, int line)
{
    LocationFile = file;
    LocationLine = line;
}

#ifdef __GNUC__
static void _ReportError(const char *Format, ...) __attribute__((format (printf,1,2) ));
#endif

static void _ReportError(const char *Format, ...)
{
   va_list ArgList;

   va_start(ArgList, Format);
   printf("%s:%d: Test failed: ", LocationFile, LocationLine);
   vprintf(Format, ArgList);
   Failures++;
}

static DWORD ConvertRVAToDiskOffset(DWORD RVA, DWORD SectionHeaderCount, const IMAGE_SECTION_HEADER *SectionHeaders)
{
   const IMAGE_SECTION_HEADER *SectionHeader;

   for (SectionHeader = SectionHeaders; SectionHeader < SectionHeaders + SectionHeaderCount; SectionHeader++)
   {
      if (SectionHeader->VirtualAddress <= RVA && RVA < SectionHeader->VirtualAddress + SectionHeader->Misc.VirtualSize)
         return SectionHeader->PointerToRawData + (RVA - SectionHeader->VirtualAddress);
   }

   return 0;
}

static BOOL DllPresent(const char *DllName)
{
   HMODULE DllModule;

   DllModule = LoadLibraryExA(DllName, NULL, LOAD_LIBRARY_AS_DATAFILE);
   if (DllModule != NULL)
      FreeLibrary(DllModule);

   return DllModule != NULL;
}

/*
 * When launching an app that implicitly links against a DLL that's not present, a message box
 * will be shown "Unable to locate component". The child process waits until this message is
 * dismissed.
 * This can happen when running tests for a system DLL on a Windows version which does not include
 * that DLL. It messes up our testing because the child just hangs around until the timeout expires,
 * taking up testing time and generating a timeout error.
 * Since the message is produced by the child process before any application code is run, we can't
 * suppress it using SetErrorMode() or ProcessDefaultHardErrorMode. It is possible to suppress using
 * the registry value ErrorMode in HKEY_LOCAL_MACHINE\CurrentControlSet\Control\Windows but that has
 * a global effect.
 * So instead we just dive into the executable's import table, determine which modules are being
 * imported and check if they are present.
 */
static BOOL AllImportedDllsPresent(const char *TestExeName)
{
   HANDLE TestExe;
   IMAGE_DOS_HEADER DosHeader;
   IMAGE_NT_HEADERS NTHeaders;
   const IMAGE_DATA_DIRECTORY *DataDirectoryImportTable;
   IMAGE_SECTION_HEADER *SectionHeaders;
   IMAGE_IMPORT_DESCRIPTOR *ImportDescriptors;
   const IMAGE_IMPORT_DESCRIPTOR *ImportDescriptor;
   DWORD NR;
   DWORD NewPos;
   DWORD FileOffset;
   char ModuleName[_MAX_PATH];
   BOOL Found;
   BOOL AllPresent;

   TestExe = CreateFileA(TestExeName, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
   if (TestExe == INVALID_HANDLE_VALUE)
   {
      ReportError("Can't open test executable %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }

   if (! ReadFile(TestExe, &DosHeader, sizeof(IMAGE_DOS_HEADER), &NR, NULL) || NR != sizeof(IMAGE_DOS_HEADER))
   {
      CloseHandle(TestExe);
      ReportError("Can't read DOS header from %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }
   if (DosHeader.e_magic != IMAGE_DOS_SIGNATURE)
   {
      CloseHandle(TestExe);
      ReportError("%s does not start with a valid DOS header\n", TestExeName);
      return FALSE;
   }

   NewPos = SetFilePointer(TestExe, DosHeader.e_lfanew, NULL, FILE_BEGIN);
   if (NewPos == INVALID_SET_FILE_POINTER && GetLastError() != ERROR_SUCCESS)
   {
      CloseHandle(TestExe);
      ReportError("Can't move to NT headers in %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }

   if (! ReadFile(TestExe, &NTHeaders, sizeof(IMAGE_NT_HEADERS), &NR, NULL) || NR != sizeof(IMAGE_NT_HEADERS))
   {
      CloseHandle(TestExe);
      ReportError("Can't read NT headers from %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }
   if (NTHeaders.Signature != IMAGE_NT_SIGNATURE || NTHeaders.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR_MAGIC)
   {
      CloseHandle(TestExe);
      ReportError("%s does not contain valid NT headers expected 0x%08x/0x%04x found 0x%08lx/0x%04x\n", TestExeName,
             IMAGE_NT_SIGNATURE, IMAGE_NT_OPTIONAL_HDR_MAGIC, NTHeaders.Signature, NTHeaders.OptionalHeader.Magic);
      return FALSE;
   }
   DataDirectoryImportTable = NTHeaders.OptionalHeader.DataDirectory + IMAGE_DIRECTORY_ENTRY_IMPORT;
   if (DataDirectoryImportTable->VirtualAddress == 0 || DataDirectoryImportTable->Size == 0)
   {
      CloseHandle(TestExe);
      ReportError("%s does not contain valid a valid import table (RVA 0x%lx size 0x%lx)\n", TestExeName,
             DataDirectoryImportTable->VirtualAddress, DataDirectoryImportTable->Size);
      return FALSE;
   }

   SectionHeaders = (IMAGE_SECTION_HEADER*) malloc(NTHeaders.FileHeader.NumberOfSections * sizeof(IMAGE_SECTION_HEADER));
   if (SectionHeaders == NULL)
   {
      CloseHandle(TestExe);
      ReportError("Unable to allocate memory for section headers\n");
      return FALSE;
   }
   if (! ReadFile(TestExe, SectionHeaders, NTHeaders.FileHeader.NumberOfSections * sizeof(IMAGE_SECTION_HEADER), &NR, NULL) ||
       NR != NTHeaders.FileHeader.NumberOfSections * sizeof(IMAGE_SECTION_HEADER))
   {
      free(SectionHeaders);
      CloseHandle(TestExe);
      ReportError("Can't read section headers from %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }

   ImportDescriptors = (IMAGE_IMPORT_DESCRIPTOR*) malloc(DataDirectoryImportTable->Size);
   if (ImportDescriptors == NULL)
   {
      free(SectionHeaders);
      CloseHandle(TestExe);
      ReportError("Unable to allocate memory for import directory\n");
      return FALSE;
   }
   FileOffset = ConvertRVAToDiskOffset(DataDirectoryImportTable->VirtualAddress,
                                       NTHeaders.FileHeader.NumberOfSections, SectionHeaders);
   if (FileOffset == 0)
   {
      free(ImportDescriptors);
      free(SectionHeaders);
      CloseHandle(TestExe);
      ReportError("Can't locate import directory in %s\n", TestExeName);
      return FALSE;
   }
   NewPos = SetFilePointer(TestExe, FileOffset, NULL, FILE_BEGIN);
   if (NewPos == INVALID_SET_FILE_POINTER && GetLastError() != ERROR_SUCCESS)
   {
      free(ImportDescriptors);
      free(SectionHeaders);
      CloseHandle(TestExe);
      ReportError("Can't move to import directory in %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }

   if (! ReadFile(TestExe, ImportDescriptors, DataDirectoryImportTable->Size, &NR, NULL) || NR != DataDirectoryImportTable->Size)
   {
      free(ImportDescriptors);
      free(SectionHeaders);
      CloseHandle(TestExe);
      ReportError("Can't read import directory from %s, error %lu\n", TestExeName, GetLastError());
      return FALSE;
   }

   AllPresent = TRUE;
   for (ImportDescriptor = ImportDescriptors;
        (char *) ImportDescriptor < (char *) ImportDescriptors + DataDirectoryImportTable->Size && ImportDescriptor->Name != 0;
        ImportDescriptor++)
   {
      FileOffset = ConvertRVAToDiskOffset(ImportDescriptor->Name, NTHeaders.FileHeader.NumberOfSections, SectionHeaders);
      if (FileOffset == 0)
      {
         free(ImportDescriptors);
         free(SectionHeaders);
         CloseHandle(TestExe);
         ReportError("Can't locate import module name in %s\n", TestExeName);
         return FALSE;
      }
      NewPos = SetFilePointer(TestExe, FileOffset, NULL, FILE_BEGIN);
      if (NewPos == INVALID_SET_FILE_POINTER && GetLastError() != ERROR_SUCCESS)
      {
         free(ImportDescriptors);
         free(SectionHeaders);
         CloseHandle(TestExe);
         ReportError("Can't move to import module name in %s, error %lu\n", TestExeName, GetLastError());
         return FALSE;
      }

      if (! ReadFile(TestExe, ModuleName, sizeof(ModuleName), &NR, NULL))
      {
         free(ImportDescriptors);
         free(SectionHeaders);
         CloseHandle(TestExe);
         ReportError("Can't read import directory from %s, error %lu\n", TestExeName, GetLastError());
         return FALSE;
      }

      Found = FALSE;
      for (NewPos = 0; ! Found && NewPos < NR; NewPos++)
         Found = ModuleName[NewPos] == '\0';
      if (! Found)
      {
         free(ImportDescriptors);
         free(SectionHeaders);
         CloseHandle(TestExe);
         ReportError("Import module name is too long in %s\n", TestExeName);
         return FALSE;
      }

      if (! DllPresent(ModuleName))
      {
         if (AllPresent)
         {
            printf("%s:0 Test skipped: required DLL %s", TestName, ModuleName);
            AllPresent = FALSE;
         }
         else
            printf(", %s", ModuleName);
      }
   }

   free(ImportDescriptors);
   free(SectionHeaders);
   CloseHandle(TestExe);

   if (! AllPresent)
   {
      printf(" is missing\n");
      Skips++;
   }

   return AllPresent;
}

int main(int argc, char *argv[])
{
   int Arg;
   DWORD TimeOut;
   BOOL UsageError;
   char TestExeFullName[_MAX_PATH];
   char *TestExeFileName;
   const char *Suffix;
   const char *Subtest;
   int TestArg;
   char *CommandLine;
   int CommandLen;
   STARTUPINFOA StartupInfo;
   PROCESS_INFORMATION ProcessInformation;
   DWORD WaitStatus;
   DWORD ExitCode;
   
   TimeOut = INFINITE;
   CommandLine = NULL;
   Arg = 1;
   UsageError = FALSE;
   while (Arg < argc && ! UsageError)
   {
      if ((argv[Arg][0] == '-' || argv[Arg][0] == '/') && strlen(argv[Arg]) == 2)
      {
         if (argc <= Arg + 1)
            UsageError = TRUE;
         else if (argv[Arg][1] =='t')
         {
            char *EndPtr;
            TimeOut = (DWORD) strtoul(argv[Arg + 1], &EndPtr, 10) * 1000;
            if (*EndPtr != '\0')
            {
               fprintf(stderr, "Invalid TimeOut value %s\n", argv[Arg + 1]);
               exit(1);
            }
         }
         else
            UsageError = TRUE;
         Arg += 2;
      }
      else
      {
         if (GetFullPathNameA(argv[Arg], countof(TestExeFullName), TestExeFullName, &TestExeFileName) == 0)
         {
            fprintf(stderr, "Can't determine full path of test executable %s, error %lu\n",
                    argv[Arg], GetLastError());
            exit(1);
         }
         Suffix = strstr(TestExeFileName, "_test.exe");
         if (Suffix == NULL)
            Suffix = strstr(TestExeFileName, "_test64.exe");
         if (Suffix == NULL)
            Suffix = strchr(TestExeFileName, '.');
         if (Suffix == NULL)
            strcpy(TestName, TestExeFileName);
         else
         {
            strncpy(TestName, TestExeFileName, Suffix - TestExeFileName);
            TestName[Suffix - TestExeFileName] = '\0';
         }
         Subtest = (Arg + 1 < argc ? argv[Arg + 1] : "");

         CommandLen = strlen(TestExeFullName) + 3;
         for (TestArg = Arg + 1; TestArg < argc; TestArg++)
            CommandLen += 3 + strlen(argv[TestArg]);

         CommandLine = (char *) malloc(CommandLen);
         if (CommandLine == NULL)
         {
            fprintf(stderr, "Unable to allocate memory for child command line\n");
            exit(1);
         }

         CommandLine[0] = '"';
         strcpy(CommandLine + 1, TestExeFullName);
         strcat(CommandLine, "\"");
         for (TestArg = Arg + 1; TestArg < argc; TestArg++)
         {
            strcat(CommandLine, " \"");
            strcat(CommandLine, argv[TestArg]);
            strcat(CommandLine, "\"");
         }

         Arg = argc;
      }
   }
   if (CommandLine == NULL)
      UsageError = TRUE;
   if (UsageError)
   {
      fprintf(stderr, "Usage: %s [-t TimeOut] TestExecutable.exe [TestParameter...]\n", argv[0]);
      exit(1);
   }

   printf("%s:%s start - -\n", TestName, Subtest);

   if (! AllImportedDllsPresent(TestExeFullName))
   {
      printf("%s: %u tests executed (0 marked as todo, %u failures), %u skipped.\n", TestName, Failures, Failures, Skips);
      printf("%s:%s done (%u)\n", TestName, Subtest, Failures);
      exit(0);
   }

   fflush(stdout);

   StartupInfo.cb = sizeof(STARTUPINFOA);
   GetStartupInfoA(&StartupInfo);
   StartupInfo.dwFlags |= STARTF_USESTDHANDLES;
   StartupInfo.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
   StartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
   StartupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);

   if (! CreateProcessA(NULL, CommandLine, NULL, NULL, TRUE, CREATE_DEFAULT_ERROR_MODE, NULL, NULL, &StartupInfo, &ProcessInformation))
   {
      fprintf(stderr, "CreateProcess failed with error %lu\n", GetLastError());
      exit(1);
   }

   CloseHandle(ProcessInformation.hThread);
   WaitStatus = WaitForSingleObject(ProcessInformation.hProcess, TimeOut);
   if (WaitStatus != WAIT_OBJECT_0)
   {
      switch(WaitStatus)
      {
      case WAIT_FAILED:
         fprintf(stderr, "Wait for child failed, error %lu\n", GetLastError());
         break;

      case WAIT_TIMEOUT:
         break;

      default:
         fprintf(stderr, "Unexpected return value %lu from wait for child\n", WaitStatus);
         break;
      }

      ExitCode = WaitStatus;
      if (! TerminateProcess(ProcessInformation.hProcess, 257))
         fprintf(stderr, "TerminateProcess failed with error %lu\n", GetLastError());

      switch (WaitForSingleObject(ProcessInformation.hProcess, 5000))
      {
      case WAIT_OBJECT_0:
         break;

      case WAIT_FAILED:
         fprintf(stderr, "Wait for terminate failed, error %lu\n", GetLastError());
         break;

      case WAIT_TIMEOUT:
         fprintf(stderr, "Can't kill child\n");
         break;

      default:
         fprintf(stderr, "Unexpected return value %lu from wait for terminate\n", WaitStatus);
         break;
      }
   }
   else
   {
      if (! GetExitCodeProcess(ProcessInformation.hProcess, &ExitCode))
      {
         ExitCode = 259;
         fprintf(stderr, "Can't get child exit code, error %lu\n", GetLastError());
      }
   }
   CloseHandle(ProcessInformation.hProcess);

   printf("%s:%s done (%lu)\n", TestName, Subtest, ExitCode);

   return 0;
}
