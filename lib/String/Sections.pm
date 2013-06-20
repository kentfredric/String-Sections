use strict;
use warnings;

package String::Sections;

# ABSTRACT: Extract labeled groups of sub-strings from a string.

=begin MetaPOD::JSON v1.1.0

{
    "namespace":"String::Sections",
    "interface":"class",
    "inherits":"Moo::Object"
}

=end MetaPOD::JSON

=cut

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
  my $result = $sections->load_list( @lines );
  # TODO
  # $sections->load_string( $string );
  # $sections->load_filehandle( $fh );
  #
  # $sections->merge( $other_sections_object );

  my @section_names = $result->section_names();
  if ( $result->has_section( 'section_label' ) ) {
    my $string_ref = $result->section( 'section_label' );
    ...
  }

=cut

use 5.010001;
use Moo;
use Sub::Quote qw{ quote_sub };
use String::Sections::Result;

=head1 DEVELOPMENT

This code is still new and under development.

All the below facets are likely to change at some point, but don't
largely contribute to the API or usage of this module.

=over 4

=item * Needs Perl 5.10.1

To make some of the development features easier.

=back

=cut

=head1 Recommended Use with Data::Handle

This modules primary inspiration is Data::Section, but intending to split and decouple many of the
internal parts to add leverage to the various behaviors it contains.

Data::Handle solves part of a problem with Perl by providing a more reliable interface to the __DATA__ section in a file that is not impeded by various things that occur if its attempted to be read more than once.

In future, I plan on this being the syntax for connecting Data::Handle with this module to emulate Data::Section:

  my $dh = Data::Handle->new( __PACKAGE__ );
  my $ss = String::Sections->new( stop_at_end => 1 );
  my $result = $ss->load_filehandle( $dh );

This doesn't implicitly perform any of the inheritance tree magic Data::Section does,
but its also planned on making that easy to do when you want it with C<< ->merge( $section ) >>

For now, the recommended code is not so different:

  my $dh = Data::Handle->new( __PACKAGE__ );
  my $ss = String::Sections->new( stop_at_end => 1 );
  my $result  = $ss->load_list( <$dh> );

Its just somewhat less efficient.

=cut

=head1 SIGNIFICANT CHANGES

=head2 Since 0.1.x

=head3 API

In 0.1.x, api was

    my $section = String::Sections->new();
    $section->load_*( $source );
    $section->section_names

This was inherently fragile, and allowed weird things to occur when people
tried to get data from it without it being populated yet.

So starting with 0.2.0, the api is

    my $section = String::Sections->new();
    my $result  = $section->load_*( $source );
    $result->section_names;

And the main class is a factory for L<< C<String::Sections::Result>|String::Sections::Result >> objects.

=cut

=method new

=method new( %args )

  my $object = String::Sections->new();

  my $object = String::Sections->new( attribute_name => 'value' );

=cut

sub _croak { require Carp; goto &Carp::croak; }

sub __add_line {

  my ( $self, $stash, $line ) = @_;

  if ( ${$line} =~ $self->header_regex ) {
    $stash->set_current("$1");
    $stash->append_data_to_current_section();
    return 1;    # 1 is next.
  }

  # not valid for lists because lists are not likely to have __END__ in them.
  if ( $self->stop_at_end ) {
    return 0 if ${$line} =~ $self->document_end_regex;
  }

  if ( $self->ignore_empty_prelude ) {
    return 1 if not $stash->has_current and ${$line} =~ $self->empty_line_regex;
  }

  if ( not $stash->has_current ) {
    _croak( 'bogus data section: text outside named section. line: ' . ${$line} );
  }

  if ( $self->enable_escapes ) {
    my $regex = $self->line_escape_regex;
    ${$line} =~ s{$regex}{}msx;
  }

  $stash->append_data_to_current_section($line);

  return 1;
}

=method load_list

=method load_list ( @strings )

=method load_list ( \@strings )

  my @strings = <$fh>;

  my $result = $string_section->load_list( @strings );

  my $result = $string_section->load_list( \@strings );


This method handles data as if it had been slopped in unchomped from a filehandle.

Ideally, each entry in @strings will be terminated with $/ , as the collated data from each section
is concatenated into a large singular string, e.g.:

  $result = $string_section->load_list("__[ Foo ]__\n", "bar\n", "baz\n" );
  $section_foo = $result->section('Foo')
  # bar
  # baz

  $result = $s_s->load_list("__[ Foo ]__\n", "bar", "baz" );
  $result->section('Foo');
  # barbaz

  $object->load_list("__[ Foo ]__", "bar", "baz" ) # will not work by default.

This behaviour may change in the future, but this is how it is with the least effort for now.

=cut

sub load_list {
  my ( $self, @rest ) = @_;

  my $result_ob = String::Sections::Result->new();

  if ( $self->default_name ) {
    $result_ob->set_current( $self->default_name );
    $result_ob->add_data_to_current_section();
  }

  for my $line (@rest) {
    my $result = $self->__add_line( $result_ob, \$line );
    next if $result;
    last if not $result;

  }
  return $result_ob;
}

=method load_string

TODO

=cut

sub load_string {
  my ( $self, $string ) = @_;
  return _croak('Not Implemented');
}

=method load_filehandle

=method load_filehandle( $fh )

  $object->load_filehandle( $fh )

=cut

sub load_filehandle {
  my ( $self, $fh ) = @_;

  my $result_ob = String::Sections::Result->new();

  if ( $self->_default_name ) {
    $result_ob->set_current( $self->_default_name );
    $result_ob->append_data_to_current_section();
  }
  while ( defined( my $line = <$fh> ) ) {
    my $result = $self->__add_line( $result_ob, \$line, );
    next if $result;
    last if not $result;
  }

  return $result_ob;

}

#
# Defines accessors *_regex and _*_regex , that are for public and private access respectively.
# Defaults to _default_*_regex.

for (qw( header_regex empty_line_regex document_end_regex line_escape_regex )) {
  has $_ => (
    is  => 'rw',
    isa => sub {
      ( ref $_[0] and ref $_[0] eq 'Regexp' ) or do {
        die "Not a Regexp";
        }
    },
    builder => '_default_' . $_,
    lazy    => 1,
  );
}

# String | Undef accessors.
#

for (qw( default_name )) {

  has $_ => (
    is  => 'rw',
    isa => sub {
      if ( defined $_[0] ) { require Params::Classify; Params::Classift::check_string( $_[0] ); }
    },
    builder => '_default_' . $_,
    lazy    => 1,
  );
}

# Boolean Accessors
for (qw( stop_at_end ignore_empty_prelude enable_escapes )) {
  has $_ => (
    is  => 'rw',
    isa => sub {
      if ( ref $_[0] ) { _croak("$_[0] is not a valid boolean value"); }
    },
    builder => '_default_' . $_,
    lazy    => 1,
  );
}

# Default values for various attributes.

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
