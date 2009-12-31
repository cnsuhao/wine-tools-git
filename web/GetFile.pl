#!/usr/bin/perl -Tw

use strict;

use Apache2::Const -compile => qw(REDIRECT);
use CGI;
use Fcntl;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Steps;

sub GetFile
{
  my ($Request, $JobKey, $StepKey) = @_;

  # Validate and untaint
  if (! ($JobKey =~ m/^(\d+)$/))
  {
    return !1;
  }
  $JobKey = $1;
  if (! ($StepKey =~ m/^(\d+)$/))
  {
    return !1;
  }
  $StepKey = $1;

  my $Job = CreateJobs()->GetItem($JobKey);
  if (! defined($Job))
  {
    return !1;
  }
  my $Step = $Job->Steps->GetItem($StepKey);
  if (! defined($Step))
  {
    return !1;
  }

  my $FileName = "$DataDir/jobs/$JobKey/$StepKey/" . $Step->FileName;
  if (! sysopen(FILE, $FileName, O_RDONLY))
  {
    return !1;
  }
  my $BlkSize = (stat FILE)[11] || 16384;
  my $ImageBytes;
  my $ImageSize = 0;
  my $Len;
  while ($Len = sysread(FILE, $ImageBytes, $BlkSize, $ImageSize))
  {
    if (! defined($Len))
    {
      close FILE;
      return !1;
    }
    $ImageSize += $Len;
  }
  close FILE;
 
  # Date in the past
  $Request->headers_out->add("Expires", "Sun, 25 Jul 1997 05:00:00 GMT");
  
  # always modified
  $Request->headers_out->add("Last-Modified", (scalar gmtime) . " GMT");
  
  # HTTP/1.1
  $Request->headers_out->add("Cache-Control", "no-cache, must-revalidate, " .
                                              "post-check=0, pre-check=0");
  
  # HTTP/1.0
  $Request->headers_out->add("Pragma", "no-cache");
  
  # Binary file
  $Request->content_type("application/octet-stream");
  $Request->headers_out->add("Content-Disposition",
                             'attachment; filename="' . $Step->FileName . '"');

  print $ImageBytes;

  return 1;
}

my $Request = shift;

my $CGIObj = CGI->new($Request);
my $JobKey = $CGIObj->param("JobKey");
my $StepKey = $CGIObj->param("StepKey");
if (! GetFile($Request, $JobKey, $StepKey))
{
  $Request->headers_out->set("Location", "/");
  $Request->status(Apache2::Const::REDIRECT);
}

exit;
