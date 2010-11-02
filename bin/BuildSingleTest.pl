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

sub InfoMsg
{
  my $oldumask = umask(002);
  if (open LOGFILE, ">>$LogDir/BuildSingleTest.log")
  {
    print LOGFILE @_;
    close LOGFILE;
  }
  umask($oldumask);
}

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
  my ($PatchFile, $PatchType, $BaseName) = @_;

  my $NeedMakefile = 0;
  my $NeedMakeInclude = !1;
  my $NeedBuildDeps = !1;
  my $NeedImplib = !1;
  my $NeedAutoconf = !1;
  my $NeedConfigure = !1;
  if (open (FH, "<$PatchFile"))
  {
    my $Line;
    while (defined($Line = <FH>) &&
           ($NeedMakefile == 0 || ! $NeedMakeInclude || ! $NeedBuildDeps ||
            ! $NeedImplib || ! $NeedAutoconf || ! $NeedConfigure))
    {
      if ($Line =~ m=^diff.*tests/Makefile\.in=)
      {
        $NeedMakefile = 1;
      }
      elsif ($Line =~ m=^diff.*include/.*\.idl=)
      {
        $NeedMakeInclude = 1;
      }
      elsif ($Line =~ m=^diff.*\.spec=)
      {
        $NeedBuildDeps = 1;
      }
      elsif ($PatchType eq "dlls" && $Line =~ m=^diff.*$BaseName/Makefile\.in=)
      {
        $NeedImplib = 1;
      }
      elsif ($Line =~ m=^diff.*configure\.ac=)
      {
        $NeedAutoconf = 1;
      }
      elsif ($Line =~ m=^diff.*configure=)
      {
        $NeedConfigure = 1;
      }
    }
    close FH;
  }

  InfoMsg "Applying patch\n";
  system("git apply --verbose --directory=$DataDir/wine-git $PatchFile " .
         ">> $LogDir/BuildSingleTest.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Patch failed to apply\n";
    return (-1, $NeedMakeInclude, $NeedBuildDeps, $NeedImplib, $NeedConfigure);
  }

  if ($NeedAutoconf && ! $NeedConfigure)
  {
    InfoMsg "Running autoconf\n";
    system("cd $DataDir/wine-git; autoconf --output configure configure.ac" .
           ">> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
       LogMsg "Autoconf failed\n";
       return (-1, $NeedMakeInclude, $NeedBuildDeps, $NeedImplib,
               $NeedConfigure);
    }
    $NeedConfigure = 1;
  }

  return ($NeedMakefile, $NeedMakeInclude, $NeedBuildDeps, $NeedImplib,
          $NeedConfigure);
}

sub BuildTestExecutable
{
  my ($BaseName, $PatchType, $Bits, $NeedConfigure, $NeedMakefile,
      $NeedMakeInclude, $NeedBuildDeps, $NeedImplib) = @_;

  if ($NeedConfigure)
  {
    InfoMsg "Reconfigure $Bits-bit crossbuild\n";
    my $Host = ($Bits == 64 ? "x86_64-w64-mingw32" : "i686-pc-mingw32");
    system("cd $DataDir/build-mingw$Bits && " .
           "../wine-git/configure --host=$Host " .
           "--with-wine-tools=../build-native --without-x --without-freetype " .
           ">> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Reconfigure of $Bits-bit crossbuild failed\n";
      return !1;
    }
  }

  if ($NeedMakeInclude || $NeedConfigure)
  {
    InfoMsg "Recreating include/Makefile\n";
    system("cd $DataDir/build-mingw${Bits}; ./config.status --file include/Makefile:Make.vars.in:include/Makefile.in >> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Recreation of include/Makefile failed\n";
      return !1;
    }

    system("make -C $DataDir/build-mingw${Bits}/include " .
           ">> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Make in include dir failed\n";
      return !1;
    }
  }

  if ($NeedImplib || $NeedConfigure)
  {
    InfoMsg "Rebuilding $BaseName import lib\n";
    system("cd $DataDir/build-mingw${Bits}; ./config.status --file $PatchType/$BaseName/Makefile:Make.vars.in:$PatchType/$BaseName/Makefile.in >> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Unable to regenerate $PatchType/$BaseName/Makefile\n";
    }
    else
    {
      system("make -C $DataDir/build-mingw${Bits}/$PatchType/$BaseName " .
             "lib$BaseName.a >> $LogDir/BuildSingleTest.log 2>&1");
      if ($? != 0)
      {
        LogMsg "Make of import library failed\n";
      }
    }
  }

  if ($NeedMakefile || $NeedConfigure)
  {
    InfoMsg "Recreating tests/Makefile\n";
    system("cd $DataDir/build-mingw${Bits}; ./config.status --file $PatchType/$BaseName/tests/Makefile:Make.vars.in:$PatchType/$BaseName/tests/Makefile.in >> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Recreation of tests/Makefile failed\n";
      return !1;
    }
  }

  if ($NeedBuildDeps)
  {
    InfoMsg "Making build dependencies\n";
    system("cd $DataDir/build-mingw${Bits}; make __builddeps__ >> $LogDir/BuildSingleTest.log 2>&1");
    if ($? != 0)
    {
      LogMsg "Making build dependencies failed\n";
      return !1;
    }
  }

  my $TestsDir = "$DataDir/build-mingw${Bits}/$PatchType/$BaseName/tests";
  my $TestExecutable = "$TestsDir/$BaseName";
  if ($PatchType eq "programs")
  {
    $TestExecutable .= ".exe";
  }
  $TestExecutable .= "_test.exe";
  unlink($TestExecutable);
 
  InfoMsg "Making test executable\n";
  system("make -C $TestsDir >> $LogDir/BuildSingleTest.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Make failed\n";
    return !1;
  }
  if (! -f $TestExecutable)
  {
    LogMsg "Make didn't produce a $TestExecutable file\n";
    return !1;
  }

  return 1;
}

$ENV{PATH} = "/usr/bin:/bin:/usr/local/mingw/bin:/usr/local/mingw64/bin";
delete $ENV{ENV};

# Start with clean logfile
unlink("$LogDir/BuildSingleTest.log");

my ($PatchFile, $PatchType, $BaseName, $BitIndicators) = @ARGV;
if (! $PatchFile || ! $PatchType || ! $BaseName || !$BitIndicators)
{
  FatalError "Usage: BuildSingleTest.pl <patchfile> <patchtype> <basename> <bits>\n";
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

if ($PatchType =~ m/^patch(dlls|programs)$/)
{
  $PatchType = $1;
}
else
{
  FatalError "Invalid patch type $PatchType\n";
}

if ($BaseName =~ m/^([\w_.\-]+)$/)
{
  $BaseName = $1;
}
else
{
  FatalError "Invalid DLL base name $BaseName\n";
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

my ($NeedMakefile, $NeedMakeInclude, $NeedBuildDeps, $NeedImplib,
    $NeedConfigure) = ApplyPatch($PatchFile, $PatchType, $BaseName);
if ($NeedMakefile < 0)
{
  exit(1);
}

if ($Run32 && ! BuildTestExecutable($BaseName, $PatchType, 32,
                                    $NeedConfigure, 0 < $NeedMakefile,
                                    $NeedMakeInclude, $NeedBuildDeps,
                                    $NeedImplib))
{
  exit(1);
}
if ($Run64 && ! BuildTestExecutable($BaseName, $PatchType, 64,
                                    $NeedConfigure, 0 < $NeedMakefile,
                                    $NeedMakeInclude, $NeedBuildDeps,
                                    $NeedImplib))
{
  exit(1);
}

LogMsg "ok\n";
exit;
