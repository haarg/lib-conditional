package lib::NoWorldWritable;
use strict;
use warnings;
use lib::conditional;
use Cwd;
use File::Spec;
use Fcntl ':mode';
use Carp;
our @CARP_NOT = qw(lib::conditional);

# anything 
sub import {
  my ($class, @opts) = @_;
  my $full_check;
  @opts = grep {
    !(
      $_ eq '-full' ? ( $full_check = 1 )
      : 0
    )
  } @opts;
  if (@opts) {
    croak "bad options: @opts";
  }

  for my $lib (sort keys %INC) {
    my $full_path = $INC{$lib};
    next
      if !-e $full_path;
    my $check_file = lib::conditional::maybe_pmc($full_path);
    MAC($check_file, $lib);
  }

  if ($full_check) {
    _check_dirs(@INC);
  }

  @INC = map +(ref $_ ? $_ : lib::conditional->new(\&MAC, $_)), @INC;
}

# we will always be vulnerable to race conditions, so just cache any return values
my %checked;
sub MAC {
  my ($path, $lib, $fh) = @_;
  my $full_path = Cwd::abs_path($path);
  my @path = File::Spec->splitdir($full_path);
  my @check_path;
  while (@path) {
    push @check_path, shift @path;
    my $check_path = File::Spec->catdir(@check_path);
    if (exists $checked{$check_path}) {
      next
        if $checked{$check_path};
    }
    elsif (!((stat $check_path)[2] & S_IWOTH)) {
      $checked{$check_path} = 1;
      next;
    }
    else {
      $checked{$check_path} = 0;
    }
    croak "Refusing to load "
      . (defined $lib ? "'$lib' from " : '')
      . (-d $full_path ? 'from ' : '')
      . "'$full_path', '$check_path' is world writable!";
  }
  return 1;
}

sub _check_dirs {
  my @dirs = @_;
  while (defined (my $dir = pop @dirs)) {
    opendir my $dh, $dir
      or die "can't read $dir: $!";
    my @entries =
      map "$dir/$_",
      grep !/^\.\.?$/,
      readdir $dh;
    unshift @dirs,
      grep -d,
      @entries;
    MAC $dir;
  }
}


1;
__END__
