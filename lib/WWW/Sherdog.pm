package WWW::Sherdog;

use strict;
use warnings;
use Carp;
use Furl;
use URI;
use Web::Scraper::LibXML;
use WWW::Sherdog::Fighter;

our $VERSION = '0.01';

sub new {
    my $class = shift;
    my $self = bless +{}, $class;
    return $self;
}

sub ua {
    my $self = shift;
    unless ($self->{_ua}) {
        $self->{_ua} = Furl->new(
            agent   => join('/', __PACKAGE__, $VERSION),
            timeout => 10,
        );
    }
    return $self->{_ua};
}

sub search_fighter {
    my($self, $keyword) = @_;

    my @fighters = ();

    my $search_result = scraper {
        process 'table.fightfinder_result', 'fighter[]' => sub {
            my $node = $_;
            my @children = $node->find('tr');
            my $first = shift @children;
            unless ($first->find('td')->[0]->as_text eq 'Fighter') {
                return;
            }
            my @result = ();
            for my $child (@children) {
                my @td = $child->find('td');
                my $path = $td[1]->find('a')->[0]->attr('href');
                my $link =
                    URI->new_abs($path, 'http://www.sherdog.com/')->as_string;
                my($id) = $path =~ /(\d+)$/;
                my $name = $td[1]->find('a')->[0]->as_text;
                my $nickname = $td[2]->as_text;
                $nickname =~ s/^"(.*?)"/$1/;
                my $height = $td[3]->find('strong')->[0]->as_text;
                my $w = $td[4]->as_text;
                my($weight) = $w =~ /^([\d\.]+)\s+lbs/;
                my($weight_kg) = $w =~ /\(([\d\.]+)\s+kg\)$/;
                my $association = $td[5]->as_text;
                push @result, +{
                    id          => $id,
                    link        => $link,
                    path        => $path,
                    name        => $name,
                    nickname    => $nickname,
                    height      => $height,
                    weight      => $weight,
                    weight_kg   => $weight_kg,
                    association => $association,
                };
            }
            return @result;
        };
        process 'span.pagination', has_next => 'TEXT';
    };

    my $page = 1;
    while (1) {
        my $uri = URI->new('http://www.sherdog.com/stats/fightfinder');
        $uri->query_form(SearchTxt => $keyword, page => $page);
        my $r = $self->ua->get($uri);
        unless ($r->is_success) {
            carp $r->status_line;
            return;
        }
        my $res = $search_result->scrape($r->content);
        last unless exists $res->{fighter} && @{$res->{fighter}};
        push @fighters,
            map { WWW::Sherdog::Fighter->new($_) } @{$res->{fighter}};
        last unless exists $res->{has_next} && $res->{has_next} =~ /\bnext\b/i;
        ++$page;
    }
    return @fighters;
}

1;
__END__

=head1 NAME

WWW::Sherdog - MMA data scraper for Sherdog.pm

=head1 SYNOPSIS

 use WWW::Sherdog;
 
 my $sherdog = WWW::Sherdog->new;
 
 my($fighter) = $sherdog->search_fighter('anderson silva');
 
 if ($fighter) {
     print "name: ", $fighter->name, "\n";
     print "nickname: ", $fighter->nickname, "\n";
     print "association: ", $fighter->association, "\n";
 }

=head1 DESCRIPTION

WWW::Sherdog is

=head1 AUTHOR

Koichi Taniguchi E<lt>taniguchi@cpan.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
