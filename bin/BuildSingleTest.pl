#!/usr/bin/perl -Tw

use strict;

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use WineTestBot::Config;

sub LogMsg
{
  my $oldumask = umask(002);
  if (open LOGFILE, ">>$LogDir/BuildSingleTest.log")
  {
    print LOGFILE "BuildSingleTest: ", @_;
    close LOGFILE;
  }
  umask($oldumask);
}

sub FatalError
{
  LogMsg @_;

  exit 1;
}

sub ApplyPatch
{
  my $PatchFile = $_[0];

  my $NeedConfig = 0;
  my $StripLevel = 1;
  if (open (FH, "<$PatchFile"))
  {
    my $Line;
    while (defined($Line = <FH>) && ($NeedConfig == 0 || $StripLevel == 1))
    {
      if ($Line =~ m/RCS file|^\+\+\+.*working copy/)
      {
        $StripLevel = 0;
      }
      if ($Line =~ m=tests/Makefile\.in=)
      {
        $NeedConfig = 1;
      }
    }
    close FH;
  }

  system("patch --strip=$StripLevel --force --directory=$DataDir/wine-git " .
         "--input=$PatchFile >> $LogDir/BuildSingleTest.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Patch failed\n";
    return -1;
  }

  return $NeedConfig;
}

sub BuildTestExecutable
{
  my ($DllBaseName, $Bits, $NeedConfig) = @_;

  if ($NeedConfig)
  {
    system("cd $DataDir/build-mingw${Bits}; ./config.status dlls/$DllBaseName/tests/Makefile >> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Reconfig failed\n";
      return !1;
    }
  }

  my $TestsDir = "$DataDir/build-mingw${Bits}/dlls/$DllBaseName/tests";
  unlink("$TestsDir/${DllBaseName}_test.exe");
 
  system("make -C $TestsDir >> $LogDir/BuildSingleTest.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Make failed\n";
    return !1;
  }
  if (! -f "$TestsDir/${DllBaseName}_test.exe")
  {
    LogMsg "Make didn't produce a ${DllBaseName}_test.exe file\n";
    return !1;
  }

  return 1;
}

$ENV{PATH} = "/usr/bin:/bin:/usr/local/mingw/bin:/usr/local/mingw64/bin";
delete $ENV{ENV};

# Start with clean logfile
unlink("$LogDir/BuildSingleTest.log");

my ($PatchFile, $DllBaseName, $BitIndicators) = @ARGV;
if (! $PatchFile || ! $DllBaseName)
{
  FatalError "Usage: BuildSingleTest.pl <patchfile> <dllbasename> <bits>\n";
}

# Untaint parameters
if ($PatchFile =~ m/^([\w_.\-]+)$/)
{
  $PatchFile = "$DataDir/staging/$1";
  if (! -r $PatchFile)
  {
    FatalError "Patch file $PatchFile not readable\n";
  }
}
else
{
  FatalError "Invalid patch file $PatchFile\n";
}

if ($DllBaseName =~ m/^([\w_.\-]+)$/)
{
  $DllBaseName = $1;
}
else
{
  FatalError "Invalid DLL base name $DllBaseName\n";
}

my $Run32 = !1;
my $Run64 = !1;
if ($BitIndicators =~ m/^([\d,]+)$/)
{
  my @Bits = split /,/, $1;
  foreach my $BitsValue (@Bits)
  {
    if ($BitsValue == 32)
    {
      $Run32 = 1;
    }
    elsif ($BitsValue == 64)
    {
      $Run64 = 1;
    }
    else
    {
      FatalError "Invalid number of bits $BitsValue\n";
    }
  }
  if (! $Run32 && ! $Run64)
  {
    FatalError "Specify at least one of 32 or 64 bits\n";
  }
}
else
{
  FatalError "Invalid number of bits $BitIndicators\n";
}

my $NeedConfig = ApplyPatch($PatchFile);
if ($NeedConfig < 0)
{
  exit(1);
}

if ($Run32 && ! BuildTestExecutable($DllBaseName, 32, 0 < $NeedConfig))
{
  exit(1);
}
if ($Run64 && ! BuildTestExecutable($DllBaseName, 64, 0 < $NeedConfig))
{
  exit(1);
}

LogMsg "ok\n";
exit;
