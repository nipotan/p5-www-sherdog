package WWW::Sherdog::Fighter;

use strict;
use warnings;
use parent 'WWW::Sherdog::BaseObject';
use Carp;
use URI;
use Furl;
use Web::Scraper::LibXML;

our $VERSION = '0.01';

__PACKAGE__->_delayed_accessors(qw(
    id name nickname link path association
    weight weight_kg height height_cm class
    wins losses draws no_contests wins_breakdown losses_breakdown history
    birthday birthplace nationality
));

sub crawl_fighter {
    my($self, $content) = @_;
    my $class = ref($self) || $self;
    my %full_month = do {
        my $i = 0;
        map { $_ => ++$i }
            qw(January February March April May June
                July August September October November December);
    };

    my %month = map { substr($_, 0, 3) => $full_month{$_} } keys %full_month;

    my %match_types = (
        'Fight History'   => 'professional',
        'Amateur Fights'  => 'amateur',
        'Upcoming Fights' => 'upcoming_fight',
    );

    my %result_other_types = (
        'Draws' => 'draws',
        'N/C'   => 'no_contests',
    );

    my $fighter = scraper {
        process 'div > h1 > span.fn', name => 'TEXT';
        process 'div > h1 > span.nickname > em', nickname => 'TEXT';
        process 'div.birth_info > span > span[itemprop="birthDate"]',
            birthday => 'TEXT';
        process 'span.birthplace > span.adr > span.locality',
            birthplace => 'TEXT';
        process 'span.birthplace > strong[itemprop="nationality"]',
            nationality => 'TEXT';
        process 'div.size_info > span.height > strong', height => 'TEXT';
        process 'div.size_info > span.height', height_cm => sub {
            my($cm) = $_->as_text =~ m{([\d\.]+)\s*cm\s*$};
            return $cm;
        };
        process 'div.size_info > span.weight > strong', weight => sub {
            my($lbs) = $_->as_text =~ m{([\d\.]+)\s*lbs};
            return $lbs;
        };
        process 'div.size_info > span.weight', weight_kg => sub {
            my($kg) = $_->as_text =~ m{([\d\.]+)\s*kg};
            return $kg;
        };
        process 'span[itemprop="memberOf"] > a > span[itemprop="name"]',
            association => 'TEXT';
        process 'h6.wclass > strong.title', class => 'TEXT';
        process 'div.left_side > div[class="bio_graph"] > span.card > span.counter',
            wins => 'TEXT';
        process 'div.left_side > div[class="bio_graph"] > span.graph_tag',
            'wins_breakdown[]' => 'TEXT';
        process 'div.left_side > div.loser > span.card > span.counter',
            losses => 'TEXT';
        process 'div.left_side > div.loser > span.graph_tag',
            'losses_breakdown[]' => 'TEXT';
        process 'div.right_side > div.bio_graph > span.card', 'others[]' => sub {
            my $node = $_;
            my @spans = $node->find('span');
            my $result_type;
            my $count;
            for my $span (@spans) {
                my $class = $span->attr('class');
                if ($class eq 'result') {
                    $result_type = $result_other_types{$span->as_text};
                }
                elsif ($class eq 'counter') {
                    $count = $span->as_text;
                }
            }
            return unless defined $result_type;
            return +{ $result_type => int($count) };
        };
        process 'div.fight_history', 'history[]' => sub {
            my $node = $_;
            my $url = $self->_guess_url;
            my($header) = $node->find('h2');
            my @result = ();
            my $header_line = $header->as_text;
            return unless $match_types{$header_line};
            my %result = ();
            my $match_type = $match_types{$header_line};
            my($table)  = $node->find('table');
            if ($match_type eq 'upcoming_fight') {
                my @divs = $table->find('div');
                my @h3s = $table->find('h3');
                my $opponent = +{};
                for my $h3 (@h3s) {
                    my $fighter = $h3->find('a')->[0];
                    my $path = $fighter->attr('href');
                    my $link = URI->new_abs($path, $url)->as_string;
                    next if $self->link eq $link;
                    my($id) = $path =~ /(\d+)$/;
                    my $name = $h3->as_text;
                    $opponent = +{
                        id   => $id,
                        link => $link,
                        path => $path,
                        name => $name,
                    };
                    next;
                }
                my $event_name = $table->find('h2')->[0]->as_text;
                my @d = split /\s*,?\s+/, $table->find('h4')->[0]->as_text;
                my $date =
                    sprintf('%d-%02d-%02d', $d[2], $full_month{$d[0]}, $d[1]);
                unshift @{$result{$match_type}}, +{
                    opponent => $opponent,
                    event    => +{ name => $event_name },
                    date     => $date,
                };
            }
            else {
                my @tr = $table->find('tr');
                shift @tr;
                for my $fight (@tr) {
                    my @td = $fight->find('td');
                    my $result = $td[0]->as_text;
                    my $opponent = $td[1]->find('a')->[0];
                    my $path = $opponent->attr('href');
                    my($id) = $path =~ /(\d+)$/;
                    my $link = URI->new_abs($path, $url)->as_string;
                    my $name = $opponent->as_text;
                    my $event = $td[2]->find('a')->[0];
                    my $event_path = $event->attr('href');
                    my($event_id) = $event_path =~ /(\d+)$/;
                    my $event_link = URI->new_abs($event_path, $url)->as_string;
                    my $event_name = $event->as_text;
                    my @d = split m{\s*/\s*}, $td[2]->find('span')->[-1]->as_text;
                    my $date =
                        sprintf('%d-%02d-%02d', $d[2], $month{$d[0]}, $d[1]);
                    my($ref_node) = $td[3]->find('span');
                    my $referee = $ref_node->as_text;
                    $ref_node->delete;
                    my($method, $note) =
                        $td[3]->as_text =~ m{^(.+)\s+\((.+?)\)$};
                    my $round = $td[4]->as_text;
                    my $time  = $td[5]->as_text;
                    $result{$match_type} ||= [];
                    unshift @{$result{$match_type}}, +{
                        result   => $result,
                        opponent => +{
                            id   => $id,
                            link => $link,
                            path => $path,
                            name => $name,
                        },
                        event    => +{
                            id   => $event_id,
                            link => $event_link,
                            path => $event_path,
                            name => $event_name,
                        },
                        date     => $date,
                        referee  => $referee,
                        method   => $method,
                        note     => $note,
                        round    => $round,
                        time     => $time,
                    };
                }
            }
            return \%result;
        };
    };

    return $fighter->scrape($content);
}

sub _fixup_data {
    my($self, $res) = @_;

    my %breakdown_type = (
        'KO/TKO'      => 'knockout',
        'SUBMISSIONS' => 'submission',
        'DECISIONS'   => 'decision',
        'OTHERS'      => 'others',
    );

    for my $result (qw(wins losses)) {
        my $key = $result . '_breakdown';
        if ($res->{$key}) {
            my %bd = ();
            for my $data (@{$res->{$key}}) {
                my($num, $type) = $data =~ m{^(\d+)\s+(.+?)\s+\(\d+\%\)$};
                $bd{$breakdown_type{$type}} = $num;
            }
            $res->{$key} = \%bd;
        }
    }

    my %history = ();
    for my $history (@{$res->{history} || []}) {
        my($k, $v) = each %$history;
        $history{$k} = $v;
    }
    $res->{history} = \%history;

    for my $other (@{delete $res->{others} || []}) {
        my($k, $v) = each %$other;
        $res->{$k} = $v;
    }

    for my $key (keys %$res) {
        $self->{$key} = $res->{$key};
    }
}

1;
