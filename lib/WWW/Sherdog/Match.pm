package WWW::Sherdog::Match;

use strict;
use warnings;
use parent 'Class::Accessor::Fast';

__PACKAGE__->mk_accessors(qw(date referee method note round time winner loser));

1;

=head1 NAME

WWW::Sherdog::Match - match object for Sherdog.com

=cut
