// GenFixEnv.cpp : Defines the entry point for the console application.
//

#include <stdio.h>
#include <windows.h>

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
   BOOL NoErr;
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

   fclose(BatchFile);

   return 0;
}
