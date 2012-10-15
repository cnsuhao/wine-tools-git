/*
 * Generates a batch file that sets up the environment.
 * This can be used in case the mechanism for running a process in the VM
 * does not properly set up the environment for the currently logged in user.
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
#include <windows.h>
#include <shlobj.h>

static void GenerateFromReg(FILE *BatchFile)
{
   LONG Err;
   HKEY UserEnvironment;
   DWORD Index;
   char ValueName[256];
   DWORD ValueNameSize;
   DWORD Type;
   char Data[1024];
   DWORD DataSize;

   Err = RegOpenKeyExA(HKEY_CURRENT_USER, "Environment", 0, KEY_QUERY_VALUE,
                       &UserEnvironment);
   if (Err != ERROR_SUCCESS)
      return;

   Index = 0;
   do
   {
      ValueNameSize = sizeof(ValueName);
      DataSize = sizeof(Data);
      Err = RegEnumValueA(UserEnvironment, Index, ValueName, &ValueNameSize,
                            NULL, &Type, (LPBYTE) Data, &DataSize);
      if (Err == ERROR_SUCCESS)
      {
         if (Type == REG_EXPAND_SZ)
         {
            char Expanded[sizeof(Data)];
            DWORD ExpandedSize;
            ExpandedSize = ExpandEnvironmentStringsA(Data, Expanded,
                                                     sizeof(Expanded));
            memcpy(Data, Expanded, ExpandedSize);
            Type = REG_SZ;
         }
         if (Type == REG_SZ)
         {
            if (strcmp(ValueName, "TEMP") != 0 && strcmp(ValueName, "TMP") != 0)
               fprintf(BatchFile, "SET \"%s=%s\"\n", ValueName, Data);
            else
            {
               char Short[sizeof(Data)];
               GetShortPathNameA(Data, Short, sizeof(Short));
               fprintf(BatchFile, "SET \"%s=%s\"\n", ValueName, Short);
            }
         }
      }
      Index++;
   }
   while (Err == ERROR_SUCCESS);

   RegCloseKey(UserEnvironment);
}

static void GenerateUserProfile(FILE *BatchFile)
{
   BOOL (WINAPI *pOpenProcessToken)(HANDLE,DWORD,PHANDLE);
   BOOL (WINAPI *pGetUserProfileDirectoryA)(HANDLE,LPSTR,LPDWORD);
   HMODULE hadvapi32 = GetModuleHandleA("advapi32.dll");
   HMODULE huserenv = LoadLibraryA("userenv.dll");
   HANDLE Token;
   char Data[1024];
   DWORD DataSize;

   pOpenProcessToken = (void *)GetProcAddress(hadvapi32, "OpenProcessToken");
   pGetUserProfileDirectoryA = (void *)GetProcAddress(huserenv,
                                                       "GetUserProfileDirectoryA");
   if (pOpenProcessToken == NULL || pGetUserProfileDirectoryA == NULL)
      return;

   if (! pOpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &Token))
      return;
   DataSize = sizeof(Data);
   if (! pGetUserProfileDirectoryA(Token, Data, &DataSize))
      return;
   fprintf(BatchFile, "SET \"USERPROFILE=%s\"\n", Data);
   CloseHandle(Token);
}

static void GenerateCSIDL(FILE *BatchFile)
{
   char Path[_MAX_PATH]; 
   HMODULE Mod;
   HRESULT (WINAPI *pSHGetFolderPathA)(HWND, int, HANDLE, DWORD, LPSTR);
   HRESULT Res;

   Mod = LoadLibraryA("shell32.dll");
   pSHGetFolderPathA = (void *) GetProcAddress(Mod, "SHGetFolderPathA");
   if (pSHGetFolderPathA == NULL)
   {
      FreeLibrary(Mod);
      Mod = LoadLibraryA("shfolder.dll");
      pSHGetFolderPathA = (void *) GetProcAddress(Mod, "SHGetFolderPathA");
   }
   if (pSHGetFolderPathA != NULL)
   {
      if (GetEnvironmentVariable("APPDATA", Path, sizeof(Path)) == 0)
      {
         Res = pSHGetFolderPathA(NULL, CSIDL_APPDATA, NULL,
                                 SHGFP_TYPE_CURRENT, Path);
         if (SUCCEEDED(Res))
            fprintf(BatchFile, "SET \"APPDATA=%s\"\n", Path);
      }
      if (GetEnvironmentVariable("LOCALAPPDATA", Path, sizeof(Path)) == 0)
      {
         Res = pSHGetFolderPathA(NULL, CSIDL_LOCAL_APPDATA, NULL,
                                 SHGFP_TYPE_CURRENT, Path);
         if (SUCCEEDED(Res))
            fprintf(BatchFile, "SET \"LOCALAPPDATA=%s\"\n", Path);
      }
   }
   FreeLibrary(Mod);
}

int main(int argc, char *argv[])
{
   FILE *BatchFile;
   if (argc != 2)
   {
      fprintf(stderr, "Usage: GenFixEnv <BatchFile>\n");
      exit(1);
   }

   BatchFile = fopen(argv[1], "w");
   if (BatchFile == NULL)
   {
      perror("Unable to open output file");
      exit(1);
   }

   fprintf(BatchFile, "@echo off\n");
   GenerateFromReg(BatchFile);
   GenerateUserProfile(BatchFile);
   GenerateCSIDL(BatchFile);

   fclose(BatchFile);

   return 0;
}
