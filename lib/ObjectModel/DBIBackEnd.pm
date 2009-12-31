use strict;

use DBI;
use ObjectModel::BackEnd;

package ObjectModel::DBIBackEnd;

use Time::Local;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::BackEnd Exporter);
@EXPORT = qw(&UseDBIBackend);

sub GetDb
{
  my $self = shift;

  if (! defined($self->{Db}))
  {
    $self->{Db} = DBI->connect(@{$self->{ConnectArgs}});
  }

  return $self->{Db};
}

sub ToDb
{
  my $self = shift;
  my ($Value, $PropertyDescriptor) = @_;

  if ($PropertyDescriptor->GetClass eq "Basic")
  {
    if ($PropertyDescriptor->GetType() eq "B")
    {
      if ($Value)
      {
        $Value = "Y";
      }
      else
      {
        $Value = "N";
      }
    }
    elsif ($PropertyDescriptor->GetType() eq "DT")
    {
      if (defined($Value))
      {
        if ($Value == 0)
        {
          $Value = undef;
        }
        else
        {
          my ($Sec, $Min, $Hour, $MDay, $Mon, $Year, $WDay, $YDay, $IsDst) = gmtime($Value);
          $Value = sprintf "%04d-%02d-%02d %02d:%02d:%02d",
                           $Year + 1900, $Mon + 1, $MDay, $Hour, $Min, $Sec;
        }
      }
    }
  }

  return $Value;
}

sub FromDb
{
  my $self = shift;
  my ($Value, $PropertyDescriptor) = @_;

  if ($PropertyDescriptor->GetClass eq "Basic")
  {
    if ($PropertyDescriptor->GetType() eq "B")
    {
      $Value = ($Value eq "Y");
    }
    elsif ($PropertyDescriptor->GetType() eq "DT")
    {
      if (defined($Value))
      {
        if ($Value eq "0000-00-00 00:00:00")
        {
          $Value = undef;
        }
        else
        {
          my ($Year, $Month, $Day, $Hour, $Min, $Sec) =
            ($Value =~ m/^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$/);
          $Value = timegm($Sec, $Min, $Hour, $Day, $Month - 1, $Year - 1900);
        }
      }
    }
  }

  return $Value;
}

sub BuildKeyWhere
{
  my $self = shift;
  my ($PropertyDescriptors, $ColPrefix, $Where) = @_;

  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    if ($PropertyDescriptor->GetIsKey())
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        if ($Where ne "")
        {
          $Where .= " AND ";
        }
        $Where .= $ColPrefix . $ColName . " = ?";
      }
    }
  }

  return $Where;
}

sub BuildFieldList
{
  my $self = shift;
  my $PropertyDescriptors = $_[0];

  my $Fields = "";
  foreach my $PropertyDescriptor (@$PropertyDescriptors)
  {
    foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
    {
      if ($Fields ne "")
      {
        $Fields .= ", ";
      }
      $Fields .= $ColName;
    }
  }

  return $Fields;
}

sub LoadCollection
{
  my $self = shift;
  my $Collection = $_[0];

  my $Fields = $self->BuildFieldList($Collection->GetPropertyDescriptors());

  my $Where = "";
  my @Data;
  my ($MasterColNames, $MasterColValues) = $Collection->GetMasterCols();
  if (defined($MasterColNames))
  {
    $Where = join(" = ? AND ", @{$MasterColNames}) . " = ?";
    push(@Data, @{$MasterColValues});
  }

  my $Filters = $Collection->GetFilters();
  foreach my $FilterProperty (keys %$Filters)
  {
    if ($Where ne "")
    {
      $Where .= " AND ";
    }
    my $PropertyDescriptor = $Collection->GetPropertyDescriptorByName($FilterProperty);
    my $FilterValues = $Filters->{$FilterProperty};
    if (@$FilterValues != 1)
    {
      $Where .= "(";
    }
    foreach my $FilterIndex (0 .. @$FilterValues - 1)
    {
      if ($FilterIndex != 0)
      {
        $Where .= " OR ";
      }
      my $ColValue = $FilterValues->[$FilterIndex];
      if ($PropertyDescriptor->GetClass() eq "Itemref")
      {
        $ColValue = $ColValue->GetKey();
      }
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        $Where .= "$ColName = ?";
        $Data[@Data] = $self->ToDb($ColValue, $PropertyDescriptor);
      }
    }
    if (@$FilterValues != 1)
    {
      $Where .= ")";
    }
  }

  my $Query = "SELECT $Fields FROM " . $Collection->GetTableName();
  if ($Where ne "")
  {
    $Query .= " WHERE $Where";
  }
  my $Statement = $self->GetDb()->prepare($Query);
  $Statement->execute(@Data);

  while (my $Row = $Statement->fetchrow_hashref())
  {
    my $Item = $Collection->CreateItem();
    foreach my $PropertyDescriptor (@{$Collection->GetPropertyDescriptors()})
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        $Item->PutColValue($ColName, $self->FromDb($Row->{$ColName},
                                                   $PropertyDescriptor));
      }
    }
    $Item->ResetModified();

    $Collection->{Items}{$Item->GetKey()} = $Item;
  }

  $Statement->finish();
}

sub LoadItem
{
  my $self = shift;
  my ($Collection, $RequestedKey) = @_;

  my $Fields = $self->BuildFieldList($Collection->GetPropertyDescriptors());

  my $Where = "";
  my @Data;
  my ($MasterColNames, $MasterColValues) = $Collection->GetMasterCols();
  if (defined($MasterColNames))
  {
    $Where = join(" = ? AND ", @{$MasterColNames}) . " = ?";
    push(@Data, @{$MasterColValues});
  }
  $Where = $self->BuildKeyWhere($Collection->GetPropertyDescriptors(), "",
                                $Where);
  push(@Data, $RequestedKey);

  my $Query = "SELECT $Fields FROM " . $Collection->GetTableName();
  if ($Where ne "")
  {
    $Query .= " WHERE $Where";
  }
  my $Statement = $self->GetDb()->prepare($Query);
  $Statement->execute(@Data);

  my $Item = undef;
  if (my $Row = $Statement->fetchrow_hashref())
  {
    $Item = $Collection->CreateItem();
    foreach my $PropertyDescriptor (@{$Collection->GetPropertyDescriptors()})
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        $Item->PutColValue($ColName, $self->FromDb($Row->{$ColName},
                                                   $PropertyDescriptor));
      }
    }
    $Item->ResetModified();
  }

  $Statement->finish();

  return $Item;
}

sub BuildInsertStatement
{
  my $self = shift;
  my ($TableName, $PropertyDescriptors, $MasterColNames) = @_;

  my $Fields = "";
  my $PlaceHolders = "";
  if (defined($MasterColNames))
  {
    foreach my $ColName (@$MasterColNames)
    {
      if ($Fields ne "")
      {
        $Fields .= ", ";
        $PlaceHolders .= ", ";
      }
      $Fields .= $ColName;
      $PlaceHolders .= "?";
    }
  }

  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
    {
      if ($Fields ne "")
      {
        $Fields .= ", ";
        $PlaceHolders .= ", ";
      }
      $Fields .= $ColName;
      $PlaceHolders .= "?";
    }
  }

  return "INSERT INTO $TableName ($Fields) VALUES($PlaceHolders)";
}

sub GetInsertData
{
  my $self = shift;
  my $MasterColValues = shift;
  my $Item = shift;

  my @Data;
  if (defined($MasterColValues))
  {
    push(@Data, @$MasterColValues);
  }

  foreach my $PropertyDescriptor (@{$Item->GetPropertyDescriptors()})
  {
    foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
    {
      $Data[@Data] = $self->ToDb($Item->GetColValue($ColName),
                                 $PropertyDescriptor);
    }
  }

  return \@Data;
}

sub BuildUpdateStatement
{
  my $self = shift;
  my ($TableName, $PropertyDescriptors, $MasterColNames) = @_;

  my $Fields = "";
  foreach my $PropertyDescriptor (@{$PropertyDescriptors})
  {
    if (! $PropertyDescriptor->GetIsKey())
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        if ($Fields ne "")
        {
          $Fields .= ", ";
        }
        $Fields .= $ColName . " = ?";
      }
    }
  }

  my $Where = "";
  if (defined($MasterColNames))
  {
    $Where = join(" = ? AND ", @{$MasterColNames}) . " = ?";
  }
  $Where = $self->BuildKeyWhere($PropertyDescriptors, "", $Where);

  return "UPDATE $TableName SET $Fields WHERE $Where";
}

sub GetUpdateData
{
  my $self = shift;
  my $MasterColValues = shift;
  my $Item = shift;

  my @Data;
  foreach my $PropertyDescriptor (@{$Item->GetPropertyDescriptors()})
  {
    if (! $PropertyDescriptor->GetIsKey())
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        $Data[@Data] = $self->ToDb($Item->GetColValue($ColName),
                                   $PropertyDescriptor);
      }
    }
  }

  if (defined($MasterColValues))
  {
    push(@Data, @$MasterColValues);
  }

  foreach my $PropertyDescriptor (@{$Item->GetPropertyDescriptors()})
  {
    if ($PropertyDescriptor->GetIsKey())
    {
      foreach my $ColName (@{$PropertyDescriptor->GetColNames()})
      {
        $Data[@Data] = $Item->GetColValue($ColName);
      }
    }
  }

  return \@Data;
}

sub SaveCollection
{
  my $self = shift;
  my $Collection = shift;

  my ($MasterColNames, $MasterColValues) = $Collection->GetMasterCols();
  my $UpdateQuery = $self->BuildUpdateStatement($Collection->GetTableName(),
                                                $Collection->GetPropertyDescriptors(),
                                                $MasterColNames);
  my $UpdateStatement = $self->GetDb()->prepare($UpdateQuery);

  my $InsertQuery = $self->BuildInsertStatement($Collection->GetTableName(),
                                                $Collection->GetPropertyDescriptors(),
                                                $MasterColNames);
  my $InsertStatement = $self->GetDb()->prepare($InsertQuery);

  foreach my $Key (@{$Collection->GetKeysNoLoad()})
  {
    my $Item = $Collection->GetItem($Key);
    if ($Item->GetIsNew())
    {
      $InsertStatement->execute(@{$self->GetInsertData($MasterColValues,
                                                       $Item)});

      foreach my $PropertyDescriptor (@{$Collection->{PropertyDescriptors}})
      {
        if ($PropertyDescriptor->GetIsKey() &&
            $PropertyDescriptor->GetClass() eq "Basic" &&
            $PropertyDescriptor->GetType() eq "S")
        {
          my $ColNames = $PropertyDescriptor->GetColNames;
          if (scalar @{$ColNames} != 1)
          {
            die "Sequence property spans multiple columns";
          }

          $Item->PutColValue(@{$ColNames}[0], $self->GetDb()->{'mysql_insertid'});
          $Collection->KeyChanged($Key, $Item->GetKey());
        }
      }

      $Item->OnSaved();
    }
    elsif ($Item->GetIsModified())
    {
      $UpdateStatement->execute(@{$self->GetUpdateData($MasterColValues, $Item)});
      $Item->OnSaved();
    }
  }

  $InsertStatement->finish();
  $UpdateStatement->finish();
}

sub SaveItem
{
  my $self = shift;
  my $Item = $_[0];

  my $Query;
  my ($MasterColNames, $MasterColValues) = $Item->GetMasterCols();
  if ($Item->GetIsModified())
  {
    $Query = $self->BuildUpdateStatement($Item->GetTableName(),
                                         $Item->GetPropertyDescriptors(),
                                         $MasterColNames);
  }
  elsif ($Item->GetIsNew())
  {
    die "Internal error: Need to save new items via collection";
  }
  else
  {
    return;
  }

  my $Statement = $self->GetDb()->prepare($Query);
  $Statement->execute(@{$self->GetUpdateData($MasterColValues, $Item)});

  $Statement->finish();
}

sub DeleteItem
{
  my $self = shift;
  my $Item = shift;

  my $Where = "";
  my @Data;
  my ($MasterColNames, $MasterColValues) = $Item->GetMasterCols();
  if (defined($MasterColNames))
  {
    $Where = join(" = ? AND ", @{$MasterColNames}) . " = ?";
    push(@Data, @{$MasterColValues});
  }
  $Where = $self->BuildKeyWhere($Item->GetPropertyDescriptors(), "",
                                $Where);
  push(@Data, $Item->GetKey());

  my $Statement = $self->GetDb()->prepare("DELETE FROM " .
                                          $Item->GetTableName() .
                                          " WHERE " . $Where);
  $Statement->execute(@Data);
  $Statement->finish();

  return undef;
}

sub DeleteAll
{
  my $self = shift;
  my $Collection = shift;

  my $Where = "";
  my @Data;
  my ($MasterColNames, $MasterColValues) = $Collection->GetMasterCols();
  if (defined($MasterColNames))
  {
    $Where = join(" = ? AND ", @{$MasterColNames}) . " = ?";
    push(@Data, @{$MasterColValues});
  }

  my $Query = "DELETE FROM " . $Collection->GetTableName();
  if ($Where ne "")
  {
    $Query .= " WHERE " . $Where;
  }
  my $Statement = $self->GetDb()->prepare($Query);
  $Statement->execute(@Data);
  $Statement->finish();

  return undef;
}

sub UseDBIBackEnd
{
  my $class = shift;

  $ObjectModel::BackEnd::ActiveBackEnd = $class->new();
  $ObjectModel::BackEnd::ActiveBackEnd->{ConnectArgs} = \@_;
}
1;
