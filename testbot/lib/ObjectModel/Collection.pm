# Copyright 2009 Ge van Geldorp
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA

use strict;

package ObjectModel::Collection;

=head1 NAME

ObjectModel::Collection - Base class for item collections

=head1 DESCRIPTION

Provides a set of methods to manipulate a collection of objects, and in
particular load and save them to a database table using ObjectModel::BackEnd.
Also provides a set of filtering methods to specify the set of objects we are
interested in so only those objects are retrieved from the database.

Note that there may be multiple collections corresponding to a given table at
the same time. This is how one retrieves the objects based on different
criteria.

=cut

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(&new);

use ObjectModel::BackEnd;
use ObjectModel::Item;
use ObjectModel::PropertyDescriptor;

sub new
{
  my $class = shift;
  my $TableName = shift;
  my $CollectionName = shift;
  my $ItemName = shift;
  my $PropertyDescriptors = shift;
  my $MasterObject = $_[0];

  my $MasterColNames;
  my $MasterColValues;
  if (defined($MasterObject))
  {
    ($MasterColNames, $MasterColValues) = $MasterObject->GetMasterKey();
  }

  my $self = {TableName           => $TableName,
              CollectionName      => $CollectionName,
              ItemName            => $ItemName,
              PropertyDescriptors => $PropertyDescriptors,
              MasterColNames      => $MasterColNames,
              MasterColValues     => $MasterColValues,
              Filters             => {},
              Items               => undef};
  $self = bless $self, $class;
  $self->_initialize(@_);
  return $self;
}

sub _initialize
{
}

sub GetPropertyDescriptors
{
  my $self = shift;

  return $self->{PropertyDescriptors};
}

sub GetPropertyDescriptorByName
{
  my $self = shift;

  my $Name = shift;
  foreach my $PropertyDescriptor (@{$self->{PropertyDescriptors}})
  {
    if ($PropertyDescriptor->GetName() eq $Name)
    {
      return $PropertyDescriptor;
    }
  }

  return undef;
}

sub GetTableName
{
  my $self = shift;

  return $self->{TableName};
}

sub GetCollectionName
{
  my $self = shift;

  return $self->{CollectionName};
}

sub GetItemName
{
  my $self = shift;

  return $self->{ItemName};
}

sub Load
{
  my $self = shift;

  $self->GetBackEnd()->LoadCollection($self);

  $self->{Loaded} = 1;
}

sub Add
{
  my $self = shift;

  my $NewItem = $self->CreateItem();
  $NewItem->InitializeNew($self);
  $self->{Items}{$NewItem->GetKey()} = $NewItem;

  $self->{Loaded} = 1;

  return $NewItem;
}

sub GetKeysNoLoad
{
  my $self = shift;

  my @Keys = keys %{$self->{Items}};
  return \@Keys;
}

sub GetKeys
{
  my $self = shift;

  if (! $self->{Loaded})
  {
    $self->Load();
  }

  return $self->GetKeysNoLoad();
}

sub GetItem
{
  my $self = shift;

  my $Key = shift;
  if (! defined($Key))
  {
    return undef;
  }

  if (! exists($self->{Items}{$Key}))
  {
    my $NewItem = $self->GetBackEnd()->LoadItem($self, $Key);
    if (defined($NewItem))
    {
      $self->{Items}{$NewItem->GetKey()} = $NewItem;
    }
    return $NewItem;
  }

  my $Item = undef;
  if (exists($self->{Items}{$Key}))
  {
    $Item = $self->{Items}{$Key};
  }

  return $Item;
}

sub ItemExists
{
  my $self = shift;
  my $Key = $_[0];

  if (! defined($Key))
  {
    return !1;
  }

  if (! $self->{Loaded})
  {
    $self->Load();
  }

  return exists($self->{Items}{$Key});
}

sub GetItems
{
  my $self = shift;

  if (! $self->{Loaded})
  {
    $self->Load();
  }

  my @Items = values %{$self->{Items}};
  return \@Items;
}

sub IsEmpty
{
  my $self = shift;

  if (! $self->{Loaded})
  {
    $self->Load();
  }

  return scalar(keys %{$self->{Items}}) == 0;
}

sub CombineKey
{
  my $self = shift;

  my $CombinedKey = join("#@#", @_);
  return $CombinedKey;
}

sub SplitKey
{
  my $self = shift;

  my $CombinedKey = $_[0];
  my @KeyComponents = split /#@#/, $CombinedKey;

  return @KeyComponents;
}

sub Validate
{
  my $self = shift;

  foreach my $Item (values %{$self->{Items}})
  {
    if ($Item->GetIsNew() || $Item->GetIsModified())
    {
      (my $ErrProperty, my $ErrMessage) = $Item->Validate();
      if (defined($ErrMessage))
      {
        return ($Item->GetKey(), $ErrProperty, $ErrMessage);
      }
      if ($Item->GetIsNew())
      {
        my $HasSequenceKey = !1;
        my $ErrProperty, my $ErrMessage;
        foreach my $PropertyDescriptor (@{$self->{PropertyDescriptors}})
        {
          if ($PropertyDescriptor->GetIsKey())
          {
            $ErrProperty = $PropertyDescriptor->GetName();
            $ErrMessage = $Item->$ErrProperty;
            if ($PropertyDescriptor->GetClass() eq "Basic" &&
                $PropertyDescriptor->GetType() eq "S")
            {
              $HasSequenceKey = 1;
            }
          }
        }
        if (! $HasSequenceKey)
        {
          my $ExistingItem = $self->GetBackEnd()->LoadItem($self, $Item->GetKey());
          if (defined($ExistingItem))
          {
            $ErrMessage = $self->GetItemName() . $ErrMessage .
                          " already exists";
            return ($Item->GetKey(), undef, $ErrMessage);
          }
        }
      }
    }
  }

  return (undef, undef, undef);
}

sub SaveNoValidate
{
  my $self = shift;

  $self->GetBackEnd()->SaveCollection($self);

  foreach my $PropertyDescriptor (@{$self->GetPropertyDescriptors()})
  {
    if ($PropertyDescriptor->GetClass() eq "Detailref")
    {
      foreach my $Item (values %{$self->{Items}})
      {
        my $Detail = $Item->{Details}{$PropertyDescriptor->GetName()};
        if (defined($Detail))
        {
          $Detail->SaveNoValidate();
        }
      }
    }
  }
}

sub Save
{
  my $self = shift;

  my ($ErrKey, $ErrProperty, $ErrMessage) = $self->Validate();
  if (! defined($ErrMessage))
  {
    $self->SaveNoValidate();
  }


  return ($ErrKey, $ErrProperty, $ErrMessage);
}

sub KeyChanged
{
  my $self = shift;
  my ($OldKey, $NewKey) = @_;

  my $Item = $self->{Items}{$OldKey};
  if (! defined($Item))
  {
    die "Can't change key from $OldKey to $NewKey";
  }
  delete $self->{Items}{$OldKey};
  if (defined($self->{Items}{$NewKey}))
  {
    die "Cant change key, new key $NewKey already exists";
  }
  $self->{Items}{$NewKey} = $Item;

  $Item->KeyChanged();
}

sub MasterKeyChanged
{
  my $self = shift;
  my $MasterColValues = shift;

  $self->{MasterColValues} = $MasterColValues;

  foreach my $Item (values %{$self->{Items}})
  {
    $Item->MasterKeyChanged($MasterColValues);
  }
}

sub GetMasterCols
{
  my $self = shift;

  return ($self->{MasterColNames}, $self->{MasterColValues});
}

sub DeleteItem
{
  my $self = shift;
  my $Item = shift;

  my $ErrMessage = $Item->OnDelete();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }
  my $Key = $Item->GetKey();
  $ErrMessage = $self->GetBackEnd()->DeleteItem($Item);
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  if (defined($self->{Items}{$Key}))
  {
    delete($self->{Items}{$Key});
  }

  return undef;
}

sub DeleteAll
{
  my $self = shift;

  if (! $self->{Loaded})
  {
    $self->Load();
  }
  foreach my $Item (values %{$self->{Items}})
  {
    my $ErrMessage = $Item->OnDelete();
    if (defined($ErrMessage))
    {
      return $ErrMessage;
    }
  }

  my $ErrMessage = $self->GetBackEnd()->DeleteAll($self);
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  foreach my $Key (keys %{$self->{Items}})
  {
    delete($self->{Items}{$Key});
  }

  return undef;
}

sub AddFilter
{
  my $self = shift;
  my ($PropertyName, $Value) = @_;

  $self->{Filters}{$PropertyName} = $Value;
}

sub GetFilters
{
  my $self = shift;

  return $self->{Filters};
}

1;
