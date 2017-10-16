package lib::conditional;
use strict;
use warnings;

use Carp;
use Config ();
use Errno qw(EACCES);
use constant _PMC_ENABLED => !(
  exists &Config::non_bincompat_options
    ? grep $_ eq 'PERL_DISABLE_PMC', Config::non_bincompat_options()
    : $Config::Config{ccflags} =~ /(?:^|\s)-DPERL_DISABLE_PMC\b/
);

sub import {
  my ($class, $sub, @libs) = @_;
  unshift @INC, (map +$class->new($sub, $_), @libs);
}

sub new {
  my ($class, $sub, $lib) = @_;
  bless [$sub, $lib], $class;
}

use overload
  '""' => sub { $_[0][1] },
  'bool' => sub () { 1 },
  fallback => 1,
;

sub maybe_pmc {
  my $file = shift;
  if (_PMC_ENABLED && $file =~ /\.pm\z/ && -e "${file}c" && !-d _ && !-b _) {
    $file .= 'c';
  }
  return $file;
}

# INC must be fully qualified or it will always go into main
sub lib::conditional::INC {
  my ($self, $file) = @_;
  my $full_path = $self->[1].'/'.$file;
  for my $check_file (
    (_PMC_ENABLED && $file =~ /\.pm\z/ ? $full_path.'c' : ()),
    $full_path,
  ) {
    next
      if -e $check_file ? (-d _ || -b _) : $! != EACCES;
    if (open my $fh, '<:', $check_file) {
      if ($self->[0]->($check_file, $file, $fh)) {
        $INC{$file} = $full_path;
        return $fh;
      }
    }
    elsif ($check_file ne $full_path) {
      # pmc
    }
    else {
      croak "Can't locate $file:   $check_file: $!"
    }
  }
  return ();
}

sub FILES {
  my $self = shift;
  my ($sub, $lib) = @$self;
  my @files;
  require File::Find;
  require File::Spec;
  File::Find::find({
    no_chdir => 1,
    follow_fast => 1,
    wanted => sub {
      return
        if -d || -b _;
      return
        if _PMC_ENABLED && /(.*\.pm)c\z/s && -e $1 && !-d _ && !-b _;
      my $fullpath = $_;
      my $relpath = File::Spec->abs2rel($fullpath, $lib);
      return
        if !eval { $sub->($fullpath, $relpath) };
      push @files, $relpath;
    },
  }, $lib);
  return @files;
}

1;
__END__
