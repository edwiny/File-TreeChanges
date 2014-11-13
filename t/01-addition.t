#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 5;

require_ok( 'File::TreeChanges' ) || print "Bail out!\n";

my $test_dir = "/tmp";
my $d = File::TreeChanges->new( $test_dir );

ok( defined $d, 'class instantiation' );

my $test_file_name = "$test_dir/bla";

unlink($test_file_name);
ok( ! -e $test_file_name, 'Reset test file');

$d->scan();

my $fh;

open($fh, ">$test_file_name") or die "Failed to create $test_file_name for testing";
close($fh);
$d->scan();

my @file_list = $d->new_files();

is( @file_list, 1, "One new file detected" );


my $tmp = shift @file_list;

is($tmp, $test_file_name, "Correct file is detected" );




