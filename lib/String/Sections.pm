use strict;
use warnings;

package String::Sections;

# ABSTRACT: Extract labelled groups of sub-strings from a string.

=head1 DESCRIPTION

Data Section sports the following default data markup

  __[ somename ]__
  Data
  __[ anothername ]__
  More data

This module is designed to behave as a work-alike, except on already extracted string data.

=head1 SYNOPSIS


  use String::Sections;

  my $sections = String::Sections->new();
  $sections->load_list( @lines );
  # TODO
  # $sections->load_string( $string );
  # $sections->load_filehandle( $fh );
  #
  # $sections->merge( $other_sections_object );

  my @section_names = $sections->section_names();
  if ( $sections->has_section( 'section_label' ) ) {
    my $string_ref = $sections->section( 'section_label' );
    ...
  }

=cut

use 5.010001;
use Scalar::Util qw( blessed );
use Params::Classify qw( check_regexp check_string );
use Carp qw();
use Package::Stash;

sub __subname {
  require Sub::Name;
  goto &Sub::Name::subname;
}

sub __method_list {
  my (@methods) = @_;
  my $stash = Package::Stash->new(__PACKAGE__);
  for my $methodname (@methods) {
    my $symbolname = q{&} . $methodname;
    Carp::confess("No such method to curry $methodname") if not $stash->has_symbol($symbolname);
    my $method  = $stash->get_symbol($symbolname);
    my $checker = sub {
      goto $method if blessed $_[0];
      Carp::confess("Called method $methodname as a function, Argument 0 is expected to be a blessed object");
    };
    __subname( $methodname . '<check:method>', $checker );
    $stash->remove_symbol($symbolname);
    $stash->add_symbol( $symbolname, $checker );
  }
  return 1;
}

sub __attr_list {
  my ( $validator_generator, @attrs ) = @_;
  my $stash = Package::Stash->new(__PACKAGE__);
  for my $attr (@attrs) {

    my $validator = $validator_generator->();

    my $internal_name       = '_' . $attr;
    my $mutator_name        = $attr;
    my $default_method_name = '_default_' . $attr;
    my $fieldname           = $attr;

    __subname( $fieldname . '<check:validate_value>', $validator );

    $stash->add_symbol(
      q{&} . $mutator_name,
      sub {
        my ( $self, @args ) = @_;
        if (@args) {
          my ($value) = $args[0];
          {
            local $_ = $value;
            $validator->($_);
          }
          $self->{$fieldname} = $value;
        }
        return $self->can($internal_name)->($self);
      }
    );

    $stash->add_symbol(
      q{&} . $internal_name,
      sub {
        my ($self) = @_;
        return $self->{$fieldname} if exists $self->{$fieldname};
        if ( not exists $self->{args} or not exists $self->{args}->{$fieldname} ) {
          $self->{$fieldname} = $self->can($default_method_name)->($self);
          return $self->{$fieldname};
        }
        {
          local $_ = $self->{args}->{$fieldname};
          $validator->($_);
        }
        $self->{$fieldname} = $self->{args}->{$fieldname};
        return $self->{$fieldname};
      }
    );
  }
  return 1;
}

sub new {
  my ( $class, %args ) = @_;

  $class = blessed $class if blessed $class;

  my $config = {};

  $config->{args} = \%args if %args;

  my $object = bless $config, $class;
  return $object;
}

sub load_list {
  my ( $self, @rest ) = @_;
  @rest = @{ $rest[0] } if ref $rest[0] and ref $rest[0] eq 'ARRAY';
  my %stash;
  my $current;

  if ( $self->_default_name ) {
    my $blank = q{};
    $current = $self->_default_name;
    $stash{ $self->_default_name } = \$blank;
  }

LINE: for my $line (@rest) {

    if ( $line =~ $self->_header_regex ) {
      my $blank = q{};
      $current = $1;
      $stash{$current} = \$blank;
      next LINE;
    }

    # not valid for lists because lists are not likely to have __END__ in them.
    if ( $self->_stop_at_end ) {
      last LINE if $line =~ $self->_document_end_regex;
    }

    if ( $self->_ignore_empty_prelude ) {
      next LINE if not defined $current and $line =~ $self->_empty_line_regex;
    }

    if ( not defined $current ) {
      Carp::confess(
        'bogus data section: text outside named section. line: ' . $line

          #. ' self: ' . dump $self
      );
    }

    if ( $self->_enable_escapes ) {
      my $regex = $self->_line_escape_regex;
      $line =~ s{$regex}{}msx;
    }

    ${ $stash{$current} } .= $line;
  }

  $self->{stash}     = \%stash;
  $self->{populated} = 1;
  return 1;
}

sub load_string {
  my ( $self, $string ) = @_;
  Carp::confess 'Not Implemented';
}

sub load_filehandle {
  my ( $self, $fh ) = @_;
  Carp::confess 'Not implemented';
}

sub merge {
  my ( $self, $other ) = @_;
  Carp::confess 'Not Implemented';
}

sub section_names {
  my ($self) = @_;
  return keys %{ $self->_sections };
}

sub has_section {
  my ( $self, $section ) = @_;
  return exists $self->_sections->{$section};
}

sub section {
  my ( $self, $section ) = @_;
  return $self->_sections->{$section};
}

sub _sections {
  my ($self) = @_;
  if ( not defined $self->{populated} or not $self->{populated} ) {
    Carp::confess 'Called to a section fetcher without first populating the section stash';
  }
  return $self->_stash;
}

sub _stash {
  my ($self) = @_;
  return $self->{stash} if exists $self->{stash};
  $self->{stash} = {};
  return $self->{stash};
}

sub _store_stash {
  my ( $self, $key, $value ) = @_;
  $self->_stash->{$key} = $value;
  return $value;
}

#
# Defines accessors *_regex and _*_regex , that are for public and private access respectively.
# Defaults to _default_*_regex.
#
__attr_list(
  sub {
    sub { check_regex($_) }
  },
  qw( header_regex empty_line_regex document_end_regex line_escape_regex )
);

# String | Undef accessors.
#
__attr_list(
  sub {
    sub { not defined $_ or check_string($_) }
  },
  qw( default_name ),
);

# Boolean Accessors
__attr_list(
  sub {
    sub { 1; }
  },
  qw( stop_at_end ignore_empty_prelude enable_escapes ),
);

# Go through all these methods and curry them to do method checks.

__method_list(
  qw(
    load_list load_string load_filehandle merge section_names has_section section _sections _stash _store_stash
    header_regex _header_regex
    empty_line_regex _empty_line_regex
    document_end_regex _document_end_regex
    line_escape_regex  _line_escape_regex
    default_name _default_name
    stop_at_end _stop_at_end
    ignore_empty_prelude _ignore_empty_prelude
    enable_escapes _enable_escapes
    )
);

sub _default_header_regex {
  return qr{
    \A                # start
      _+\[            # __[
        \s*           # any whitespace
          ([^\]]+?)   # this is the actual name of the section
        \s*           # any whitespace
      \]_+            # ]__
      [\x0d\x0a]{1,2} # possible cariage return for windows files
    \z                # end
    }msx;
}

sub _default_empty_line_regex {
  return qr{
      ^
      \s*   # Any empty lines before the first section get ignored.
      $
  }msx;
}

sub _default_document_end_regex {
  return qr{
    ^          # Start of line
    __END__    # Document END matcher
  }msx;
}

sub _default_line_escape_regex {
  return qr{
    \A  # Start of line
    \\  # A literal \
  }msx;
}

sub _default_default_name { return }

sub _default_stop_at_end { return }

sub _default_ignore_empty_prelude { return 1 }

sub _default_enable_escapes { return }

1;
