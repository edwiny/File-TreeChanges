package File::TreeChanges;

use 5.006;
use strict;
use warnings FATAL => 'all';
use Fcntl qw(S_ISDIR);

=head1 NAME

File::TreeChanges - Monitor directories for file addition, modification or deletion.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

  use File::TreeChanges;

  my $list = File::TreeChanges->new($ARGV[0]);

  my $done = 0;

  while(!$done) {
     $list->scan();

     foreach my $v ($list->new_files()) {
       print "New: [$v]\n";
     }

     foreach my $v ($list->removed_files()) {
       print "Removed: [$v]\n";
     }

     foreach my $v ($list->modified_files()) {
       print "Modified: [$v]\n";
	my $arr = $list->stats($v);             # return the last 2 results of stat()
	if($arr->[0][7] > $arr->[1][7]) {
	  print "$v has grown\n";
	}

     }

     sleep(1);
  }


=cut



=head1 METHODS

=item new(@directories)

Initialise the object with the specified directories to scan.

=cut

sub new {
  my $class = shift;
  my $self  = {};
  $self->{files} = {};          # the full set of files found in last scan
  $self->{new_files} = {};      # files detected to be newly added in last scan
  $self->{removed_files} = {};  # files removed since the previous scan
  $self->{include_masks} = [];  # filename masks to include files
  $self->{exclude_masks} = [];  # filename masks to exclude files
  $self->{recurse}       = 1;   # by default recurse
  set_locations($self, @_);
  bless($self, $class);
}

=item set_locations(@directories)

Set the list of directories to monitor.

=cut


sub set_locations {
  my $self = shift;
  my %tmphash;

  $self->{dirs} = undef;
  $self->{dirs} = [];
  while(my $d = shift @_) {
    $tmphash{$d} = 1;             # use hash to squash duplicates
  }
  $self->{dirs} = [ keys %tmphash ];
}

=item get_locations()

Returns list of directories being monitored

=cut



sub get_locations {
  my $self = shift;
  return(@{$self->{dirs}});
}

=item set_include_masks(@regex_patterns)

Set a list of regex patterns against which to test file names for inclusion into the set.

=cut

sub set_include_masks {
  my $self = shift;

  $self->{include_masks} = undef;
  $self->{include_masks} = [];
  while(my $d = shift @_) {
    push(@{$self->{include_masks}}, $d);
  }
}

=item get_include_masks()

Returns the list of filename inclusion patterns.

=cut

sub get_include_masks {
  my $self = shift;
  return(@{$self->{include_masks}});
}

=item set_exclude_masks(@regex_patterns)

Set the list of filename patterns to ignore. Exclusions are processed before inclusions.

=cut

sub set_exclude_masks {
  my $self = shift;

  $self->{exclude_masks} = undef;
  $self->{exclude_masks} = [];
  while(my $d = shift @_) {
    push(@{$self->{exclude_masks}}, $d);
  }
}

=item get_exclude_masks()

Returns a list of filename exclusion masks.

=cut
sub get_exclude_masks {
  my $self = shift;
  return(@{$self->{exclude_masks}});
}

=item get_locations()

Returns a list of all the files scanned.

=cut

sub files {
  my $self = shift;
  if(wantarray()) { return(keys %{$self->{files}}); }
  return($self->{files});
}

=item new_files()

Returns a list of newly added files since previous scan.

=cut
sub new_files {
  my $self = shift;
  if(wantarray()) { return(keys %{$self->{new_files}}); }
  return($self->{new_files});
}

=item removed_files()

Returns a list of files that were removed since the previous scan.

=cut
sub removed_files {
  my $self = shift;
  if(wantarray()) { return(keys %{$self->{removed_files}}); }
  return($self->{removed_files});
}

=item modified_files()

Returns a list of files that were modified since the previous scan, e.g.:
size or modification time changed.

=cut
sub modified_files {
  my $self = shift;
  if(wantarray()) { return(keys %{$self->{modified_files}}); }
  return($self->{modified_files});
}

=item set_recurse( 1 )

Controls whether sub directories are scanned recursively.
Set to true (default) or false.

=cut

sub set_recurse {
  my $self = shift;
  $self->{recurse} = shift;
}

=item stats( $filename )

Returns the results of the last 2 stat() calls on the specified file.
The first element is the result from the most recent stat.

  my $arr = $d->stats('file1');

  if($arr->[0][7] > $arr->[1][7]) {
    print "file1 has grown\n";
  }

=cut

sub stats {
  my $self = shift;
  my $filename = shift;

  return($self->{files}{$filename});
}

sub scan_dir {  
    my $self = shift;         # object
    my $path = shift;         # path to start search
    my $new_files = shift;    # ref to hash to return list of new files
    my $recurse = shift;      # flag to control recursion

    my @dirs = ();
    my $file;
    my $fullname;
    local *DIR;
    opendir(DIR, $path) or return(undef);

    while($file = readdir(DIR)) {
      next if($file eq "." or $file eq "..");

      $fullname = "$path/$file";
      my @stat_data = stat($fullname);
      
      if(S_ISDIR($stat_data[2])) {
	push(@dirs, "$fullname");
	next;
      }

      my $exclude = 0;
      foreach my $pat (@{$self->{exclude_masks}}) {
	if($file =~ /$pat/) {
	  $exclude = 1;
	  last;
	}
      }
      next if($exclude);

      if($self->{include_masks} && scalar(@{$self->{include_masks}}) > 0) {
	$exclude = 1;
	foreach my $pat (@{$self->{include_masks}}) {
	  if($file =~ /$pat/) {
	    $exclude = 0;
	    last;
	  }
	}
	next if($exclude);
      }

      $new_files->{$fullname} = \@stat_data;
    }
    closedir(DIR);
    # recurse dirs now
    if($recurse) {
      while($file = shift(@dirs))
      {
	$self->scan_dir("$file", $new_files, $recurse);
      }
    }
    return(undef);
}


sub statinfo_equals {
  my $s1 = shift;
  my $s2 = shift;


  # for effiiency we only check mtime and size
  return ( 
           $s1->[7] == $s2->[7] &&
           $s1->[9] == $s2->[9]
         );
}

=item scan()
  
  Scan the directories for changes. 
  Use files(), new_files(), and removed_files() to inspect the results.

=back

=cut

sub scan {
  my $self = shift;
  my %curset;
  my $changed = 0;

  $self->{new_files} = undef;
  $self->{new_files} = {};
  $self->{removed_files} = undef;
  $self->{removed_files} = {};
  $self->{modified_files} = undef;
  $self->{modified_files} = {};

  for my $path (@{$self->{dirs}}) {
    $self->scan_dir($path, \%curset, $self->{recurse});
  }

  # get newly added files
  while(my ($filename, $s) = each(%curset)) {

    if(!exists($self->{files}{$filename})) {
      $self->{new_files}{$filename} = 1;
      $self->{files}{$filename} = [ $s, [ 0,0,0,0,0,0,0,0,0,0,0,0,0 ] ];
      $changed++;
    } else {
      my $file_data = $self->{files}{$filename};
      unshift @{$file_data}, $s;
      $#{$file_data} = 1;
      if(!statinfo_equals($file_data->[0], 
	                  $file_data->[1])) 
      {
	$self->{modified_files}{$filename} = 1;
      }
    }
  }

  # get removed files
  while(my $f = each(%{$self->{files}})) {
    if(!exists($curset{$f})) {
      $self->{removed_files}{$f} = 1;
      $changed++;
    }
  }
  for my $f (keys %{$self->{removed_files}}) {
    delete($self->{files}{$f});
  }
  return($changed);
}

=head1 AUTHOR

Edwin Young, C<< <edwiny4096 at gmail.com> >>

=head1 LIMITATIONS

This module does not scale with very large file sets.

Only file existence is tested for, not size or modification time changes.


=head1 BUGS

Please report any bugs or feature requests to C<bug-file-treechanges at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-TreeChanges>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::TreeChanges


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-TreeChanges>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-TreeChanges>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-TreeChanges>

=item * Search CPAN

L<http://search.cpan.org/dist/File-TreeChanges/>

=back



=head1 LICENSE AND COPYRIGHT

Copyright 2014 Edwin Young.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of File::TreeChanges


